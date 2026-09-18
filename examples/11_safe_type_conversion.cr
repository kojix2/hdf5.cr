# Choose a stored type and opt into checks for lossless conversions.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "11_safe_type_conversion.h5")

HDF5.open(path, :w) do |file|
  # Explicit Int16 storage; converting all Int8 values to Int16 is safe.
  file.create_dataset("numbers", Int16, [10_i8, 20_i8, 30_i8],
    casting: HDF5::Casting::Safe) { }
end

HDF5.open(path, :r_plus) do |file|
  file.dataset("numbers", Int32) do |numbers|
    puts "Safe widening to Int32: #{numbers.read(casting: HDF5::Casting::Safe)}"
  end
  file.dataset("numbers", Int8) do |numbers|
    # Default conversions delegate to HDF5; these particular values fit Int8.
    puts "Default conversion to Int8: #{numbers.read}"
    begin
      numbers.read(casting: HDF5::Casting::Safe)
    rescue error : HDF5::TypeMismatchError
      # Array checks use datatype ranges, even when the stored values fit.
      puts "Safe narrowing rejected: #{error.message}"
    end
  end
  file.dataset("numbers", Int16) do |numbers|
    # Scalar checks use the actual value, so 42_i64 fits in Int16.
    numbers.write(42_i64, HDF5.s[0], casting: HDF5::Casting::Safe)
    puts "After safe scalar write: #{numbers.read}"
    begin
      numbers.write(40_000_i64, HDF5.s[0], casting: HDF5::Casting::Safe)
    rescue error : HDF5::TypeMismatchError
      puts "Out-of-range scalar rejected: #{error.message}"
    end
  end
end
