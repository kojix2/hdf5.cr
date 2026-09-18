# Create a numeric dataset, close the file, and read it back.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "01_hello_hdf5.h5")

# :w creates a file, replacing any previous file at this path.
# Block forms close the file and dataset automatically.
HDF5.open(path, :w) do |file|
  file.create_dataset("numbers", [10, 20, 30]) { }
end

HDF5.open(path) do |file|
  # Supply the Crystal element type when opening an existing dataset.
  file.dataset("numbers", Int32) do |numbers|
    puts "Created: #{path}"
    puts "Shape: #{numbers.shape}"
    puts "Values: #{numbers.read}" # => [10, 20, 30]
  end
end
