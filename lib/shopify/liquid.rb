# frozen_string_literal: true

require "liquid"

require_relative "comment_form"
require_relative "json_filter"
require_relative "money_filter"
require_relative "shop_filter"
require_relative "tag_filter"
require_relative "weight_filter"

default_environment = Liquid::Environment.default
default_environment.register_tag("form", CommentForm)

default_environment.register_filter(JsonFilter)
default_environment.register_filter(MoneyFilter)
default_environment.register_filter(WeightFilter)
default_environment.register_filter(ShopFilter)
default_environment.register_filter(TagFilter)
