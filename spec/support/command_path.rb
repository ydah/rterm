# frozen_string_literal: true

module SpecCommandPath
  def command_path(command)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
      path = File.join(directory, command)
      return path if File.executable?(path) && !File.directory?(path)
    end
    nil
  end

  def required_command(command, strict: false)
    path = command_path(command)
    return path if path

    message = "#{command} not installed"
    raise message if strict

    skip message
  end
end
