# frozen_string_literal: true

# Mirrors CMS lib/liquid/filters.rb — asset_url, script_tag, stylesheet_tag, image_tag
# In Liquiditor, asset_url resolves to local static file paths instead of ActiveStorage.

module Filter
  def asset_url(input)
    "/#{input}"
  end

  def script_tag(url, type = "module")
    if type.to_s.empty? || type == "default"
      %(<script src="#{url}"></script>)
    else
      %(<script src="#{url}" type="#{type}"></script>)
    end
  end

  def stylesheet_tag(url, media = "all")
    %(<link href="#{url}" rel="stylesheet" type="text/css"  media="#{media}"  />)
  end

  def image_tag(url, alt = "", css_class = "")
    %(<img src="#{url}" alt="#{alt}" class="#{css_class}" />)
  end
end
