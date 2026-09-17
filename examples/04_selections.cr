require "../src/hdf5"

# Flat values use row-major order: each consecutive group of 5 is one row.
path = File.join(Dir.tempdir, "hdf5_selections_#{Process.pid}.h5")
begin
  HDF5.open(path, :w) do |file|
    file.create_dataset("matrix", (0...20).to_a, shape: {4, 5}) do |matrix|
      row = HDF5.s[-1] # Omitted axes select all elements; integer axes are dropped.
      puts "Last row: #{matrix[row]} (shape #{row.result_shape(matrix.shape)})"

      window = HDF5.s[1..2, 1...4]
      puts "Window: #{matrix.read(window)} (shape #{window.result_shape(matrix.shape)})"
      puts "Open range: #{matrix.read(HDF5.s[..1, -2..])}"

      alternating = HDF5.s[HDF5.all, HDF5.slice(0.., step: 2)]
      puts "Every other column: #{matrix.read(alternating)}"

      # Each axis selects two blocks, each containing two consecutive elements.
      blocks = HDF5::Selection.hyperslab({0, 0}, {2, 2}, stride: {2, 3}, block: {2, 2})
      puts "Block hyperslab: #{matrix.read(blocks)}"

      matrix[HDF5.s[0, 1..3]] = [100, 101, 102]
      matrix.write(-1, HDF5.s[1.., -1]) # Broadcast one value over the selection.
      puts "After updates: #{matrix.read}"

      # The buffer length must equal the number of selected elements.
      buffer = Slice(Int32).new(4, 0)
      matrix.read_into(buffer, HDF5.s[HDF5.all, 0])
      puts "First column in a reusable buffer: #{buffer.inspect}"
      puts "Empty selection: #{matrix.read(HDF5.s[2...2])}"
    end
  end
ensure
  File.delete(path) if File.exists?(path)
end
