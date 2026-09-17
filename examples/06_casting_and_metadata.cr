require "../src/hdf5"

path = File.join(Dir.tempdir, "hdf5_casting_#{Process.pid}.h5")
begin
  HDF5.open(path, :w) do |file|
    # Explicitly choose the stored type while passing a differently typed buffer.
    file.create_dataset("integers", Int16, [10_i8, 20_i8, 30_i8], casting: HDF5::Casting::Safe).close
    data = file.open_dataset("integers")
    begin
      puts "Untyped dataset, explicit read type: #{data.read(Int32, casting: HDF5::Casting::Safe)}"
      puts "HDF5 conversion to Float32: #{data.read(Float32)}"
      begin
        data.read(Int8, casting: HDF5::Casting::Safe)
      rescue error : HDF5::TypeMismatchError
        # Array checks use datatype ranges, even if these particular values fit.
        puts "Safe narrowing rejected: #{error.message}"
      end

      # A scalar can be checked using its actual value.
      data.write(42_i64, HDF5.s[0], casting: HDF5::Casting::Safe)
      begin
        data.write(40_000_i64, HDF5.s[0], casting: HDF5::Casting::Safe)
      rescue error : HDF5::TypeMismatchError
        puts "Out-of-range scalar rejected: #{error.message}"
      end

      # Datatype handles obtained from a dataset are owned and should be closed.
      dtype = data.datatype
      begin
        puts "Stored type: #{dtype.type_class}, bytes #{dtype.size}"
        puts "Order: #{dtype.byte_order}, precision: #{dtype.precision}, offset: #{dtype.offset}"
      ensure
        dtype.close
      end
    ensure
      data.close
    end

    file.create_dataset("floats", [1.75, 2.25]) do |floats|
      puts "Default conversion to Int32: #{floats.dataset.read(Int32)}"
      begin
        floats.dataset.read(Int32, casting: HDF5::Casting::Safe)
      rescue error : HDF5::TypeMismatchError
        puts "Safe fractional conversion rejected: #{error.message}"
      end
    end
  end
ensure
  File.delete(path) if File.exists?(path)
end
