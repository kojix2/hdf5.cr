# Open files in different modes and catch errors at the operation that can fail.
require "../src/hdf5"

# This standalone script deliberately triggers native errors. Disable HDF5's
# automatic stderr stack traces so the caught Crystal exceptions are readable.
# Errors still raise exceptions; this only changes native diagnostic printing.
LibHDF5.H5open
LibHDF5.H5Eset_auto2(0, nil, nil)

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "20_file_modes_and_errors.h5")

HDF5.open(path, :w) do |file|
  file.create_dataset("original", [1, 2, 3]) { }
end
# :a opens an existing file for updates, or creates it if missing.
HDF5.open(path, :a) do |file|
  file.create_dataset("added", [4, 5, 6]) { }
end
HDF5.open(path, :r_plus) do |file|
  file.dataset("original", Int32) { |data| data.write(10, HDF5.s[0]) }
end
HDF5.open(path, :r) do |file|
  puts "Entries: #{file.keys}"
  file.dataset("original", Int32) { |data| puts "Updated values: #{data.read}" }
  begin
    file.dataset("missing", Int32) { }
  rescue error : HDF5::ObjectNotFoundError
    puts "Missing dataset: #{error.message}"
  end
end

begin
  # :x only creates a new file; it refuses to overwrite this existing file.
  HDF5.open(path, :x) { }
rescue error : HDF5::FileError
  puts "Exclusive creation refused: #{error.message}"
end

# The blocks close their resources even when an exception is raised.
