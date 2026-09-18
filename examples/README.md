# Examples

Learn hdf5.cr one topic at a time, from creating a file to processing large
datasets. The numbered tutorials follow the progression of ruby-hdf5's examples,
using Crystal's typed datasets and flat arrays.

## Run an example

Requirements: Crystal 1.20+, HDF5 2.0+, and `pkg-config`. No input files, Python,
or extra shards are needed. Compression examples require HDF5 with gzip support.

From the repository root:

```sh
crystal run examples/01_hello_hdf5.cr
```

The first example prints a file path followed by:

```text
Shape: [3]
Values: [10, 20, 30]
```

Each tutorial creates its own file under `examples/output/`. Files are kept so
you can inspect them afterward, for example with `h5dump` if installed:

```sh
h5dump examples/output/01_hello_hdf5.h5
```

You can run tutorials independently or repeat them: each run replaces only that
tutorial's output files. Example 19 creates two files; keep them together so its
external link continues to work. Generated files are ignored by Git.

Run all tutorials and advanced examples (stopping on the first failure):

```sh
for example in examples/[0-9][0-9]_*.cr examples/advanced/[0-9][0-9]_*.cr; do
  crystal run "$example" || exit "$?"
done
```

## Tutorials

Start with 01–07 for the data model, 08–12 for selections and types, and 13–20
for storage, processing, and file management. Every script includes labeled
output and comments explaining the API choices.

| Example | What you learn |
| --- | --- |
| [01_hello_hdf5.cr](01_hello_hdf5.cr) | Create a numeric dataset, close the file, and read it back |
| [02_groups_and_paths.cr](02_groups_and_paths.cr) | Organize datasets in groups and use nested paths |
| [03_multidimensional_arrays.cr](03_multidimensional_arrays.cr) | Store a matrix as a flat array with an explicit shape |
| [04_dataset_metadata.cr](04_dataset_metadata.cr) | Inspect shape, rank, element count, and stored datatype |
| [05_attributes.cr](05_attributes.cr) | Attach scalar and array metadata to files, groups, and datasets |
| [06_utf8_strings.cr](06_utf8_strings.cr) | Store Unicode text, empty string arrays, and Null strings |
| [07_scalar_empty_null.cr](07_scalar_empty_null.cr) | Distinguish a scalar, a zero-length array, and a Null dataspace |
| [08_reading_slices.cr](08_reading_slices.cr) | Read rows, columns, single values, and positive-stride selections |
| [09_writing_slices.cr](09_writing_slices.cr) | Update part of a dataset or fill a selection with one value |
| [10_read_into_existing_array.cr](10_read_into_existing_array.cr) | Reuse a Slice as a read buffer |
| [11_safe_type_conversion.cr](11_safe_type_conversion.cr) | Choose a stored type and check for lossless conversions |
| [12_boolean_and_complex.cr](12_boolean_and_complex.cr) | Store Bool and complex64/128 values |
| [13_chunked_storage.cr](13_chunked_storage.cr) | Compare contiguous, explicit chunked, and automatic chunked storage |
| [14_filters_and_integrity.cr](14_filters_and_integrity.cr) | Apply gzip, shuffle, and Fletcher32; compare stored byte counts |
| [15_growing_datasets.cr](15_growing_datasets.cr) | Append rows, resize, and fill newly allocated regions |
| [16_processing_in_blocks.cr](16_processing_in_blocks.cr) | Compute a total within an element-payload byte budget |
| [17_processing_chunks.cr](17_processing_chunks.cr) | Iterate storage chunk regions, including the partial final region |
| [18_hierarchy_management.cr](18_hierarchy_management.cr) | List, move, and delete objects |
| [19_links.cr](19_links.cr) | Create hard, soft, and external links; inspect a dangling link |
| [20_file_modes_and_errors.cr](20_file_modes_and_errors.cr) | Choose file modes and catch expected errors |

## Crystal conventions

`create_dataset` infers the element type from the supplied data. When reopening
a dataset, `file.dataset("numbers", Int32)` specifies the Crystal read type.
To select the storage type explicitly, use `create_dataset("numbers", Int16, data)`.
An untyped handle from `open_dataset` instead takes the type at read time:
`dataset.read(Int32)`.

Matrices use flat, row-major `Array(T)` or `Slice(T)` values plus `shape:`.
For example, `[1, 2, 3, 4, 5, 6]` with `shape: {2, 3}` is two rows of three
elements. `read` always returns a flat array, including for a scalar; use
`read_scalar` for one value and `read_null` for a Null marker. Nested numeric
arrays represent variable-length elements, not a rectangular matrix.

Selections use zero-based indices. `HDF5.all` selects a full axis, negative
indices count from the end, and omitted axes select all their elements. Integer
selectors drop an axis from `selection.result_shape(dataset.shape)` while the
returned data stays flat. Array writes and read buffers must match the selected
element count; scalar writes fill the selection.

The default cast policy delegates conversions to HDF5. `HDF5::Casting::Safe`
checks datatype ranges for arrays and actual values for scalars. It can reject
a narrowing array conversion even when the particular stored values would fit.

Block APIs close the supplied handles automatically. Close separately obtained
datatype and reference handles explicitly, as demonstrated in example 04 and
the advanced reference example. Closing a file also invalidates its children.

## Advanced examples

These longer examples build on the tutorials. They use temporary files and
remove them on completion, including when an exception occurs.

| Example | What you learn |
| --- | --- |
| [advanced/01_selections.cr](advanced/01_selections.cr) | Open ranges, block hyperslabs, empty selections, and selected updates |
| [advanced/02_storage_and_resize.cr](advanced/02_storage_and_resize.cr) | Combine filters and fill values; append columns and enforce maximum dimensions |
| [advanced/03_attribute_updates.cr](advanced/03_attribute_updates.cr) | Compare create/write/modify, shaped and Null attributes, and failed replacement |
| [advanced/04_string_storage.cr](advanced/04_string_storage.cr) | Partial string I/O, fixed ASCII padding, truncation checks, and NUL validation |
| [advanced/05_references_and_vlen.cr](advanced/05_references_and_vlen.cr) | Copy and close object references; store variable-length numeric elements |
| [advanced/06_streaming_measurements.cr](advanced/06_streaming_measurements.cr) | Append measurements, calculate channel means in blocks, save metadata, and query |

Run them in the same way:

```sh
crystal run examples/advanced/06_streaming_measurements.cr
```

The streaming example saves 12 rows and 3 channels. Expected channel means are
`[5.5, 11.0, 16.5]` and the last observation is `[11.0, 22.0, 33.0]`.
Its chunk region shapes are `[5, 3]`, `[5, 3]`, and `[2, 3]`.

## NASA sample data

[nasa/icesat_glas.cr](nasa/icesat_glas.cr) downloads a public ICESat GLAS HDF5
sample, reads returned waveforms, and draws a PNG heatmap with
gnuplot. See [nasa/README.md](nasa/README.md) for prerequisites, the data source,
and an explanation of the plot.

This example needs network access on its first run, plus `curl` and `gnuplot`.
It is separate from the self-contained tutorials and is not run in CI.

## File modes and expected errors

| Mode | Behavior |
| --- | --- |
| `:r` (default) | Open an existing file for reading |
| `:r_plus` / `:rw` | Open an existing file for reading and writing |
| `:w` | Create a file, replacing an existing file |
| `:x` / `:excl` | Create a file only if the path does not exist |
| `:a` | Open for reading and writing, creating the file if missing |

Examples with deliberate invalid input catch the expected exception and
continue. Example 20 disables HDF5's automatic native stack traces so the caught
Crystal exceptions are easier to read; errors still raise exceptions. Unexpected
errors stop execution so configuration problems are visible.

## HDF5 installation outside the system paths

Point pkg-config and the linker at the same HDF5 installation. On Linux:

```sh
export PKG_CONFIG_PATH=/path/to/hdf5/lib/pkgconfig
export LIBRARY_PATH=/path/to/hdf5/lib
export LD_LIBRARY_PATH=/path/to/hdf5/lib
crystal run examples/01_hello_hdf5.cr
```

Check the selected version with `pkg-config --modversion hdf5`. HDF5 1.x is
unsupported. Runtime library paths depend on the platform; `LD_LIBRARY_PATH`
above applies to Linux. HDF5 is linked at compile time; Ruby's `HDF5_LIB_PATH`
setting does not apply to these Crystal examples.
