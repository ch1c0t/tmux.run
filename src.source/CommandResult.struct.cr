include YAML::Serializable

property command : String

@[YAML::Field(converter: CommandResult::YAMLBlockStringConverter)]
property output : String

property exit_code : Int32

def initialize(@command, @output, @exit_code)
end
