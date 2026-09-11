# Regex pattern targeting standard ANSI escape sequence strings
def strip_ansi(text : String) : String
  text
    .gsub("\r\n", "\n")
    .gsub(/\e\[[0-9;]*[a-zA-Z]/, "")
end
