# frozen_string_literal: true

# Liquid FileSystem for resolving {% render 'partial' %} includes.
# Reads template files from the theme's templates/ directory on disk.
# Mirrors CMS's AccountFilesystem which reads from the database.

class FileSystem
  def initialize(path)
    @path = path
  end

  # Called by Liquid to retrieve a template file for {% render %} / {% include %}
  def read_template_file(template_path)
    full_path = "#{@path}/#{template_path}.liquid"
    puts "read_template_file #{full_path}"

    if File.exist?(full_path)
      File.read(full_path)
    else
      # Return the template path as-is if file not found (matches CMS fallback behavior)
      template_path
    end
  end
end
