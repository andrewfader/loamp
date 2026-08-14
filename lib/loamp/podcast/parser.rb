# frozen_string_literal: true

require 'rexml/document'
require 'time'

module Loamp
  module Podcast
    class Parser
      def parse(xml, url: nil)
        document = REXML::Document.new(xml.to_s)
        root = document.root
        return parse_rss(root, url) if root&.name == 'rss'
        return parse_atom(root, url) if root&.name == 'feed'

        nil
      rescue REXML::ParseException
        nil
      end

      private

      def parse_rss(root, url)
        channel = root.elements['channel']
        return nil unless channel

        title = text(channel, 'title')
        Feed.new(title: title, description: text(channel, 'description'), url: url,
                 site_url: text(channel, 'link'), image_url: rss_image(channel),
                 episodes: channel.get_elements('item').filter_map do |item|
                   rss_episode(item, title)
                 end)
      end

      def rss_episode(item, feed_title)
        media = item.elements['enclosure']&.attributes&.[]('url') ||
                item.elements['media:content']&.attributes&.[]('url')
        return nil if media.to_s.empty?

        Episode.new(
          guid: text(item, 'guid') || media, title: text(item, 'title') || 'Untitled episode',
          description: text(item, 'description') || text(item, 'content:encoded'),
          media_url: media, published_at: parse_time(text(item, 'pubDate')),
          duration: parse_duration(text(item, 'itunes:duration')),
          image_url: item.elements['itunes:image']&.attributes&.[]('href'), feed_title: feed_title
        )
      end

      def parse_atom(root, url)
        title = text(root, 'title')
        Feed.new(title: title, description: text(root, 'subtitle'), url: url,
                 site_url: atom_link(root, 'alternate'), image_url: text(root, 'logo'),
                 episodes: root.get_elements('entry').filter_map do |entry|
                   atom_episode(entry, title)
                 end)
      end

      def atom_episode(entry, feed_title)
        media = atom_link(entry, 'enclosure')
        return nil unless media

        Episode.new(
          guid: text(entry, 'id') || media, title: text(entry, 'title') || 'Untitled episode',
          description: text(entry, 'summary') || text(entry, 'content'), media_url: media,
          published_at: parse_time(text(entry, 'published') || text(entry, 'updated')),
          duration: parse_duration(text(entry, 'itunes:duration')), feed_title: feed_title
        )
      end

      def text(element, path) = element.elements[path]&.text&.strip

      def rss_image(channel)
        channel.elements['itunes:image']&.attributes&.[]('href') || text(channel, 'image/url')
      end

      def atom_link(element, relation)
        link = element.get_elements('link').find do |candidate|
          actual = candidate.attributes['rel'].to_s
          actual == relation || (relation == 'alternate' && actual.empty?)
        end
        link&.attributes&.[]('href')
      end

      def parse_time(value)
        Time.parse(value.to_s).to_i unless value.to_s.empty?
      rescue ArgumentError
        nil
      end

      def parse_duration(value)
        parts = value.to_s.split(':').map(&:to_i)
        return value.to_i if parts.length == 1

        parts.reverse.each_with_index.sum { |part, index| part * (60**index) }
      end
    end
  end
end
