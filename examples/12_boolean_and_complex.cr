# Store Bool and complex values using layouts also understood by h5py.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "12_boolean_and_complex.h5")

HDF5.open(path, :w) do |file|
  file.create_dataset("enabled", [false, true, true]) { }
  # Complex32 has Float32 components; standard Complex has Float64 components.
  file.create_dataset("complex64", [HDF5::Complex32.new(1, 2), HDF5::Complex32.new(3, -4)]) { }
  file.create_dataset("complex128", [Complex.new(1, 2), Complex.new(3, -4)]) { }
end

HDF5.open(path) do |file|
  file.dataset("enabled", Bool) { |enabled| puts "Booleans: #{enabled.read}" }
  file.dataset("complex64", HDF5::Complex32) do |values|
    # Convert explicitly to standard Complex when needed for calculations.
    puts "complex64 converted to Complex: #{values.read.map(&.to_c)}"
  end
  file.dataset("complex128", Complex) { |values| puts "complex128: #{values.read}" }
end
