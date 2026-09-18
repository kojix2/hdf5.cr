# Download a real ICESat GLAS sample and plot the received laser waveforms.
require "../../src/hdf5"

filename = "GLAH01_033_2103_001_1107_3_01_0001.H5"
url = "https://icesat.gsfc.nasa.gov/icesat/hdf5_products/data/#{filename}"
path = File.join(__DIR__, "data", filename)
output_path = File.join(__DIR__, "output", "icesat_glas_waveform.png")

abort "gnuplot is required (with the pngcairo terminal)." unless Process.find_executable("gnuplot")

unless File.file?(path)
  abort "curl is required to download the NASA sample." unless Process.find_executable("curl")
  Dir.mkdir_p(File.dirname(path))
  puts "Downloading: #{url}"
  # Only a successful download becomes the cached input; a partial file is retried.
  partial_path = "#{path}.part"
  download_status = Process.run("curl", ["--fail", "--location", "--output", partial_path, url],
    output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
  abort "Download failed; rerun to try again." unless download_status.success?
  File.rename(partial_path, path)
end

puts "Reading: #{path}"
HDF5.open(path) do |file|
  file.dataset("Data_40HZ/Waveform/RecWaveform/r_rng_wf", Float32) do |waveform|
    shape = waveform.shape
    abort "Expected a nonempty [shots, waveform samples] dataset, got #{shape}." unless shape.size == 2 && shape.all? { |size| size > 0 }
    shot_count = shape[0].to_i
    range_bin_count = shape[1].to_i
    column_count = Math.min(1040, shot_count)
    puts "Waveforms: #{shot_count} shots × #{range_bin_count} samples"

    # This sample has large compressed chunks. Read once to avoid repeatedly
    # decompressing the same chunk for adjacent groups (about 107 MiB of values).
    values = waveform.read
    # Each display column takes the maximum across a consecutive group of shots.
    heatmap = Array(Array(Float32)).new(column_count) do |column|
      first_shot = column.to_i64 * shot_count // column_count
      end_shot = (column.to_i64 + 1) * shot_count // column_count
      maxima = Array(Float32).new(range_bin_count, -Float32::INFINITY)
      (first_shot...end_shot).each do |shot|
        range_bin_count.times do |sample|
          value = values[shot * range_bin_count + sample]
          # Match the Ruby example: large fill values become -1, below the color scale.
          value = -1.0_f32 unless value.finite? && value.abs < 1_000_000
          maxima[sample] = Math.max(maxima[sample], value)
        end
      end
      maxima
    end

    # The ticks label shot order, not the compressed display-column indices.
    tick_labels = (0..4).map do |index|
      "'#{index.to_i64 * shot_count // 4}' #{index * (column_count - 1) // 4}"
    end.join(", ")

    Dir.mkdir_p(File.dirname(output_path))
    plot = Process.new("gnuplot", input: Process::Redirect::Pipe,
      output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
    begin
      plot.input << <<-GNUPLOT
        set terminal pngcairo size 1200,900
        set output #{output_path.inspect}
        set title 'ICESat GLAS returned waveform'
        set xlabel 'Shot order'
        set ylabel 'Waveform sample index'
        set cblabel 'Received 1064 nm signal (V)'
        set xtics (#{tick_labels})
        set grid
        set cbrange [0:0.5]
        set palette defined (0 'blue', 0.33 'cyan', 0.66 'yellow', 1 'red')
        set yrange [#{range_bin_count - 1}:0]
        plot '-' matrix with image notitle

        GNUPLOT
      # HDF5 is row-major by shot. gnuplot needs rows of samples across shots.
      range_bin_count.times do |sample|
        column_count.times do |column|
          plot.input << ' ' unless column == 0
          plot.input << heatmap[column][sample]
        end
        plot.input << '\n'
      end
      plot.input.puts "e"
    ensure
      plot.input.close
    end
    abort "gnuplot failed to render the heatmap." unless plot.wait.success?
    puts "Created: #{output_path}"
  end
end
