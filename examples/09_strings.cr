require "../src/hdf5"

path = File.join(Dir.tempdir, "hdf5_strings_#{Process.pid}.h5")
begin
  HDF5.open(path, :w) do |file|
    # Variable-length UTF-8 strings are the default; partial I/O is supported.
    file.create_dataset("labels", ["東京", "大阪", "京都", "札幌"],
      shape: {2, 2}, chunk: {1, 2}) do |labels|
      labels.write("未測定", HDF5.s[1])
      buffer = Slice(String).new(2, "")
      labels.read_into(buffer, HDF5.s[HDF5.all, -1])
      puts "Last column: #{buffer.inspect}"
      labels.each_chunk do |selection, values|
        puts "String chunk #{selection.result_shape(labels.shape)}: #{values}"
      end
      # each_block cannot guarantee a byte limit for variable-length payloads.
      begin
        labels.each_block(max_bytes: 64) { |_, _| }
      rescue error : HDF5::TypeMismatchError
        puts "Variable-length byte budget rejected: #{error.message}"
      end
    end

    # Fixed lengths count bytes, not characters. Safe prevents truncation.
    fixed = HDF5::StringType.fixed(8, encoding: :ascii, padding: HDF5::StringPadding::SpacePad)
    file.create_dataset("codes", ["OK", "PENDING"], string_type: fixed,
      casting: HDF5::Casting::Safe) do |codes|
      puts "Fixed ASCII strings: #{codes.read}"
      codes.each_block(max_bytes: 8) { |_, values| puts "One fixed-width block: #{values}" }
      begin
        codes.write("TOO-LONG-CODE", HDF5.s[0], casting: HDF5::Casting::Safe)
      rescue error : HDF5::TypeMismatchError
        puts "Truncation rejected: #{error.message}"
      end
      puts "Original code preserved: #{codes.read_scalar(HDF5.s[0])}"
    end

    begin
      file.create_dataset("invalid", ["embedded\0NUL"])
    rescue error : HDF5::Error
      puts "NUL rejected before creation: #{error.message}"
    end
    puts "Invalid dataset exists? #{file.exists?("invalid")}"
  end
ensure
  File.delete(path) if File.exists?(path)
end
