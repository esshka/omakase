# frozen_string_literal: true

module Omakase
  # A skill is a directory with a SKILL.md: YAML front matter says what it is,
  # the body is the guidance. The description is listed with the agent's other
  # capabilities; the body only arrives when the model calls the method — which
  # is all "loaded on demand" has to mean.
  module Skills
    CORE = File.expand_path("skills/how_to_act", __dir__)

    module_function

    # Every agent gets the how-to. Skip when a parent already defined it.
    def attach_core(agent_class)
      attach(agent_class, CORE) unless Capabilities.names(agent_class).include?(:how_to_act)
    end

    def attach(agent_class, path)
      directory = File.expand_path(path)
      front_matter, body = parse(File.read(File.join(directory, "SKILL.md"), encoding: "UTF-8"))
      name = (front_matter["name"] || File.basename(directory)).tr("-", "_").to_sym
      raise Error, "#{agent_class} already has ##{name}" if Capabilities.names(agent_class).include?(name)

      agent_class.describe(front_matter["description"].to_s)
      agent_class.define_method(name) { "#{body}\n\nFiles for this skill are in #{directory}." }
      name
    end

    # The front matter every SKILL.md in the wild is written with — CRLF too.
    def parse(text)
      match = text.match(/\A---\r?\n(.*?)\r?\n---\r?\n(.*)\z/m)
      return [{}, text.strip] unless match

      [front_matter(match[1]), match[2].strip]
    end

    # Claude Code style hints like `argument-hint: "<x>" [-p]` are not YAML; read those line by line.
    def front_matter(text)
      YAML.safe_load(text)
    rescue Psych::SyntaxError
      text.scan(/^([\w-]+):[ \t]*(.*?)\r?$/).to_h
    end
  end
end
