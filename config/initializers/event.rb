# Structured landing-page content. Repo-controlled and trusted: a few values
# contain HTML and are rendered with `raw`. Never put user-supplied data here.
module EventContent
  def self.deep_freeze(obj)
    case obj
    when Hash  then obj.each_value { |v| deep_freeze(v) }.freeze
    when Array then obj.each { |v| deep_freeze(v) }.freeze
    else obj.freeze
    end
  end
end

EVENT = EventContent.deep_freeze(
  YAML.load_file(Rails.root.join("config/event.yml"), aliases: true)
)
