# frozen_string_literal: true

require "json"

module JsonFilter
  def json(object)
    JSON.dump(object.except("collections"))
  end
end
