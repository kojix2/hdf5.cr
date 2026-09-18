# Organize datasets in groups, like files in directories.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "02_groups_and_paths.h5")

HDF5.open(path, :w) do |file|
  # require_group creates missing groups or opens an existing group.
  file.require_group("measurements/day_1") do |group|
    group.create_dataset("temperature", [20.5, 21.0, 19.5]) { }
    puts "Day 1 entries: #{group.keys}"
  end
end

HDF5.open(path) do |file|
  puts "Root entries: #{file.keys}"
  # A path from the file root can access datasets inside nested groups.
  file.dataset("measurements/day_1/temperature", Float64) do |temperature|
    puts "Temperatures: #{temperature.read}"
  end
end
