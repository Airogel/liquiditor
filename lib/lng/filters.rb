# frozen_string_literal: true

# Mirrors CMS lib/liquid/filters.rb — video_player filter
# Identical implementation to the CMS for rendering parity.

module Filters
  def video_player(input, options = {})
    ## https://gist.github.com/Kaligula0/1ff5f4e2cf1f351daeca3450f71fdcb5
    if input.match?(%r{^(?:(?:https?:)?//)?(?:(?:(?:www|m(?:usic)?)\.)?youtu(?:\.be|be\.com)/(?:shorts/|live/|v/|e(?:mbed)?/|watch(?:/|\?(?:\S+=\S+&)*v=)|oembed\?url=https?%3A//(?:www|m(?:usic)?)\.youtube\.com/watch\?(?:\S+=\S+&)*v%3D|attribution_link\?(?:\S+=\S+&)*u=(?:/|%2F)watch(?:\?|%3F)v(?:=|%3D))?|www\.youtube-nocookie\.com/embed/)([\w-]{11})[?&#]?\S*$})
      match = input.match(%r{^(?:(?:https?:)?//)?(?:(?:(?:www|m(?:usic)?)\.)?youtu(?:\.be|be\.com)/(?:shorts/|live/|v/|e(?:mbed)?/|watch(?:/|\?(?:\S+=\S+&)*v=)|oembed\?url=https?%3A//(?:www|m(?:usic)?)\.youtube\.com/watch\?(?:\S+=\S+&)*v%3D|attribution_link\?(?:\S+=\S+&)*u=(?:/|%2F)watch(?:\?|%3F)v(?:=|%3D))?|www\.youtube-nocookie\.com/embed/)([\w-]{11})[?&#]?\S*$})
      "<iframe src=\"https://www.youtube.com/embed/#{match[1]}\" class=\"#{options["class"]}\" title=\"YouTube video player\" frameborder=\"0\" allow=\"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share\" referrerpolicy=\"strict-origin-when-cross-origin\" allowfullscreen></iframe>"
    elsif input.match?(%r{(?:http|https)?:?/?/?(?:www\.)?(?:player\.)?vimeo\.com/(?:channels/(?:\w+/)?|groups/(?:[^/]*)/videos/|video/|)(\d+)(?:|/\?)})
      match = input.match(%r{(?:http|https)?:?/?/?(?:www\.)?(?:player\.)?vimeo\.com/(?:channels/(?:\w+/)?|groups/(?:[^/]*)/videos/|video/|)(\d+)(?:|/\?)})
      "<iframe src=\"https://player.vimeo.com/video/#{match[1]}\" class=\"#{options["class"]}\" frameborder=\"0\" allow=\"autoplay; fullscreen; picture-in-picture; clipboard-write\" allowfullscreen></iframe>"
    else
      "<div data-controller=\"video\" class=\"#{options["class"]}\" data-video-source-value=\"#{input}\" data-video-poster-value=\"#{options["thumbnail"]}\" data-video-id-value=\"#{options["video_id"]}\"></div>"
    end
  end
end
