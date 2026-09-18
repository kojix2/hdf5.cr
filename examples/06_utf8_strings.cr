# Store text using variable-length UTF-8 strings (the default string format).
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "06_utf8_strings.h5")

HDF5.open(path, :w) do |file|
  file.create_dataset("cities", ["東京", "大阪", "京都"]) { }
  file.create_dataset("title", "観測地点") { }
  # Empty arrays need an explicit element type in Crystal.
  file.create_dataset("empty", [] of String) { }
  file.create_dataset("missing", HDF5::Empty(String).new) { }
end

HDF5.open(path) do |file|
  file.dataset("cities", String) { |cities| puts "Cities: #{cities.read}" }
  file.dataset("title", String) { |title| puts "Title: #{title.read_scalar}" }
  file.dataset("empty", String) { |empty| puts "Empty strings: #{empty.read}" }
  file.dataset("missing", String) { |missing| puts "Null strings: #{missing.read_null.inspect}" }
end

# A Null dataset records a type without holding any values (see example 07).
# Embedded NUL characters are rejected; fixed-width strings are in advanced/04.
