# frozen_string_literal: true

module Loamp
  module Podcast
    module Opml
      module_function

      def import(xml)
        document = REXML::Document.new(xml.to_s)
        REXML::XPath.match(document, '//outline[@xmlUrl]').filter_map do |outline|
          url = outline.attributes['xmlUrl'].to_s.strip
          url unless url.empty?
        end.uniq
      rescue REXML::ParseException
        []
      end

      def export(feeds)
        document = REXML::Document.new
        document << REXML::XMLDecl.new('1.0', 'UTF-8')
        opml = document.add_element('opml', 'version' => '2.0')
        opml.add_element('head').add_element('title').text = 'LOAMP Podcasts'
        body = opml.add_element('body')
        feeds.each do |feed|
          body.add_element('outline', 'type' => 'rss', 'text' => feed.title.to_s,
                                      'title' => feed.title.to_s, 'xmlUrl' => feed.url.to_s)
        end
        output = +''
        REXML::Formatters::Pretty.new(2).write(document, output)
        output
      end
    end
  end
end
