# ICESat GLAS

Download NASA's public GLAH01 sample and write a PNG heatmap of the returned
laser waveforms. This is the Crystal counterpart of ruby-hdf5's NASA example.

## Run

Use the same Crystal 1.20+, HDF5 2.0+, and `pkg-config` environment as the other
examples. You also need `curl` and `gnuplot` with the `pngcairo` terminal.
No extra shards or Python packages are required.

From the repository root:

```sh
crystal run examples/nasa/icesat_glas.cr
```

The first run downloads approximately 31 MB into
`examples/nasa/data/GLAH01_033_2103_001_1107_3_01_0001.H5`.
Later runs reuse the local file. Downloads use a `.part` file that is renamed
only after success, so an interrupted download can be retried by rerunning.

The script prints the dataset dimensions and writes a 1200 × 900 image to
`examples/nasa/output/icesat_glas_waveform.png`. Rerunning replaces that image.
Both downloaded data and generated output are ignored by Git. This example
is excluded from CI execution because it requires an external download and
gnuplot; the regular formatting check still covers its Crystal source.

## What the plot shows

The dataset `Data_40HZ/Waveform/RecWaveform/r_rng_wf` is a matrix with one row
per laser shot and one column per waveform sample. The script opens it as
`Float32`. This sample has 51,480 shots × 544 samples, or about 107 MiB of
waveform values. Allow additional memory for HDF5 buffers and plotting.

To fit the observations into 1,040 display columns, each group is reduced to
the maximum received signal at each waveform sample index. This preserves
peaks rather than averaging them. Like the Ruby example, it reads the waveforms
in one operation: this file uses large compressed chunks, so small consecutive
reads would repeatedly decompress the same chunk. The flat Crystal array is
indexed in row-major order and transposed when sent to gnuplot.

The horizontal axis is shot order, the vertical axis is waveform sample index
(increasing downward), and color indicates received 1064 nm signal in volts
on a fixed 0–0.5 V scale. Following the Ruby example, values with absolute
magnitude at least 1,000,000 are treated as fill values and mapped to -1;
non-finite values are handled the same way. This is a visualization example,
not a replacement for product-specific scientific quality screening.

## Data source

[NASA ICESat GLAS HDF5 Sample Data](https://icesat.gsfc.nasa.gov/icesat/hdf5_products/data/index.php)
provides the sample
`GLAH01_033_2103_001_1107_3_01_0001.H5` used here.

Keep downloaded NASA data and generated figures out of commits. Cite the data
source when sharing results and do not imply NASA endorsement.
