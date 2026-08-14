# frozen_string_literal: true

module Loamp
  module Mpris
    # Ruby values as GVariants.
    #
    # ruby-gnome can build the scalar types directly but raises
    # NotImplementedError on dictionaries, which is exactly the shape MPRIS
    # metadata takes. The way through is GVariant's own text format: serialise
    # to text and let GLib parse it back with the signature we want.
    #
    # That makes escaping this module's real job. Tag values are arbitrary user
    # data — quotes, backslashes, newlines, invalid UTF-8 from a badly ripped
    # CD — and any of it reaching the parser unescaped would corrupt the whole
    # message rather than one field.
    module Variant
      DICTIONARY = 'a{sv}'

      ESCAPES = {
        '\\' => '\\\\',
        '"' => '\\"',
        "\n" => '\\n',
        "\t" => '\\t',
        "\r" => '\\r',
      }.freeze

      # Anything else in the C0/C1 control range becomes a \uXXXX escape.
      CONTROL_CHARACTERS = /[\u0000-\u001F\u007F-\u009F]/

      ESCAPABLE = /[\\"\n\t\r]|#{CONTROL_CHARACTERS}/

      module_function

      # A single value of a known D-Bus signature.
      def build(signature, value)
        return dictionary(value) if signature == DICTIONARY

        GLib::Variant.new(coerce(signature, value), signature)
      end

      # +entries+ maps a key to a [signature, value] pair. Entries whose value
      # is nil are dropped: MPRIS readers expect a missing key, not a null.
      def dictionary(entries)
        GLib::Variant.parse(dictionary_text(entries), DICTIONARY)
      end

      def dictionary_text(entries)
        pairs = entries.filter_map do |key, (signature, value)|
          next if value.nil?

          "#{quote(key)}: <#{literal(signature, value)}>"
        end

        # An empty dictionary has no type of its own to infer, so it is spelled
        # out — without which nesting one inside a variant fails to parse.
        pairs.empty? ? "@#{DICTIONARY} {}" : "{#{pairs.join(', ')}}"
      end

      # GVariant text for one value, with the type spelled out where the parser
      # could not otherwise infer it from the literal alone.
      def literal(signature, value)
        case signature
        when 's' then quote(value)
        when 'o' then "objectpath #{quote(value)}"
        when 'b' then value ? 'true' : 'false'
        when 'd' then format('%.17g', value.to_f)
        when 'i' then "int32 #{value.to_i}"
        when 'x' then "int64 #{value.to_i}"
        when 't' then "uint64 #{value.to_i}"
        when 'as' then string_array(value)
        when DICTIONARY then dictionary_text(value)
        else raise ArgumentError, "unsupported GVariant signature: #{signature}"
        end
      end

      def string_array(values)
        list = Array(values).map { |item| quote(item) }
        # An empty array carries no element type of its own, so it needs one.
        list.empty? ? '@as []' : "[#{list.join(', ')}]"
      end

      def quote(value)
        %("#{escape(value)}")
      end

      def escape(value)
        sanitize(value).gsub(ESCAPABLE) do |character|
          ESCAPES.fetch(character) { format('\\u%04X', character.ord) }
        end
      end

      # Tags come off disk as whatever bytes were written there. Anything that
      # is not valid UTF-8 is dropped rather than handed to GLib, which would
      # abort on it.
      def sanitize(value)
        text = value.to_s
        return text if text.encoding == Encoding::UTF_8 && text.valid_encoding?

        text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
      end

      # GLib is strict about the Ruby type it will accept for a signature.
      def coerce(signature, value)
        case signature
        when 'b' then value ? true : false
        when 'd' then value.to_f
        when 'i', 'x', 't' then value.to_i
        when 's', 'o' then sanitize(value)
        when 'as' then Array(value).map { |item| sanitize(item) }
        else value
        end
      end
    end
  end
end
