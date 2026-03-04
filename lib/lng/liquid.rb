# frozen_string_literal: true

require "liquid"

require_relative "filters"
require_relative "filter"
require_relative "extensions"

default_environment = Liquid::Environment.default

# Tags — mirrors CMS lib/liquid/lng_extensions.rb registration
default_environment.register_tag("template_content", Extensions::ContentForLayout)
default_environment.register_tag("github_oauth_login", Extensions::GithubOauthLogin)
default_environment.register_tag("one_click_button", Extensions::OneClickButton)
default_environment.register_tag("locale", Extensions::Locale)
default_environment.register_tag("collection_form", Extensions::CollectionForm)
default_environment.register_tag("form_for", Extensions::FormFor)
default_environment.register_tag("cms_scripts", Extensions::CmsScripts)
default_environment.register_tag("paginate", Extensions::Paginate)
default_environment.register_tag("query", Extensions::QueryTag)

# Filters
default_environment.register_filter(Filters)
default_environment.register_filter(Filter)
