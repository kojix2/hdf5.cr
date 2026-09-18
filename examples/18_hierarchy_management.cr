# List, move, and delete objects in the file hierarchy.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "18_hierarchy_management.h5")

HDF5.open(path, :w) do |file|
  file.require_group("runs/day_1") do |group|
    group.create_dataset("signal", [1, 2, 3]) { }
    puts "Original entries: #{group.keys}"
  end
  file.create_group("archive") { }
  file.move("runs/day_1/signal", "archive/signal")
  puts "Original path exists? #{file.exists?("runs/day_1/signal")}"
  puts "Archive path exists? #{file.exists?("archive/signal")}"
  file.open_group("archive") do |archive|
    puts "Archive entries: #{archive.keys}"
    archive.dataset("signal", Int32) { |signal| puts "Moved values: #{signal.read}" }
  end

  file.delete("archive/signal")
  puts "Archive path exists after deletion? #{file.exists?("archive/signal")}"
  puts "Root entries: #{file.keys}"
end

# delete removes a link. Another hard link can keep the data alive (example 19).
