# Attach small pieces of descriptive metadata to files, groups, and datasets.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "05_attributes.h5")

HDF5.open(path, :w) do |file|
  file.attrs["title"] = "Temperature experiment"
  file.create_group("measurements") do |group|
    group.attrs["location"] = "Laboratory"
    group.create_dataset("temperature", [20.5, 21.0, 19.5]) do |temperature|
      temperature.attrs["unit"] = "degC"
      temperature.attrs.create("valid_range", [-40.0, 100.0])
    end
  end
end

HDF5.open(path) do |file|
  puts "Title: #{file.attrs.get("title", String)}"
  file.open_group("measurements") do |group|
    puts "Location: #{group.attrs.get("location", String)}"
    group.dataset("temperature", Float64) do |temperature|
      puts "Unit: #{temperature.attrs.get("unit", String)}"
      puts "Valid range: #{temperature.attrs.get_array("valid_range", Float64)}"
    end
  end
end

# get reads one value; get_array reads an array. Both require the element type.
