struct CommandResult
  module YAMLBlockStringConverter
    def self.to_yaml(value : String, builder : YAML::Nodes::Builder)
      # Force the engine to render this string as a clean, literal multi-line block scalar
      builder.scalar(value, style: YAML::ScalarStyle::LITERAL)
    end
    
    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : String
      String.new(node.as(YAML::Nodes::Scalar).value)
    end
  end

  include YAML::Serializable
  
  property command : String
  
  @[YAML::Field(converter: CommandResult::YAMLBlockStringConverter)]
  property output : String
  
  property exit_code : Int32
  
  def initialize(@command, @output, @exit_code)
  end
end