# Examples

These self-contained examples use Crystal 1.20+, HDF5 2.0+, and `pkg-config`.
Run them from the repository root:

```sh
crystal run examples/01_typed_io.cr
crystal run examples/04_selections.cr
crystal run examples/12_streaming_measurements.cr
```

Each example prints its results, uses temporary HDF5 files, and removes them on
completion, including on exceptions. No input files, Python, or extra shards are
needed. Examples with deliberate invalid input catch the expected error and
continue. Storage filters require an HDF5 build with gzip support.

## Choose an example

| File | What it demonstrates |
| --- | --- |
| [01_typed_io.cr](01_typed_io.cr) | Create a matrix, reopen it with an explicit type, select rows and scalars, read into a Slice |
| [02_append_and_blocks.cr](02_append_and_blocks.cr) | Start with zero rows, append batches, inspect storage, iterate blocks and chunks |
| [03_types_and_attributes.cr](03_types_and_attributes.cr) | Quick tour of Bool, complex, Null, strings, attributes, and moving links |
| [04_selections.cr](04_selections.cr) | Negative indices, open ranges, steps, block hyperslabs, selected writes, broadcasting, empty selections |
| [05_storage_and_resize.cr](05_storage_and_resize.cr) | gzip, shuffle, Fletcher32, auto chunks, fill values, resize, append on axis 1, maximum shape |
| [06_casting_and_metadata.cr](06_casting_and_metadata.cr) | Explicit stored types, untyped reads, Safe versus default casting, byte order and precision |
| [07_attribute_updates.cr](07_attribute_updates.cr) | create/write/modify, shaped attributes, Null, optional reads, preserving values on invalid replacement |
| [08_hierarchy_and_links.cr](08_hierarchy_and_links.cr) | Groups, hard/soft/external links, typed link inspection, move, delete, dangling links |
| [09_strings.cr](09_strings.cr) | UTF-8 partial I/O, string buffers and chunks, fixed ASCII padding, Safe truncation and NUL checks |
| [10_scalar_null_and_complex.cr](10_scalar_null_and_complex.cr) | Distinguish scalar/Null/empty arrays after reopen; Bool and complex64/128 conversions |
| [11_references_and_vlen.cr](11_references_and_vlen.cr) | Copy and close references, dereference after reopen, reference attributes, variable-length numeric arrays |
| [12_streaming_measurements.cr](12_streaming_measurements.cr) | Append three-channel measurements, compute means in bounded reads, save metadata, reopen and query |

Start with 01 and 02, then use 04–11 for specific API topics. Example 12 combines
the APIs in an acquisition and analysis workflow.

Example 12 saves 12 rows and 3 channels. The saved channel means are
`[5.5, 11.0, 16.5]`, and the last observation is `[11.0, 22.0, 33.0]`.
Its chunk regions have shapes `[5, 3]`, `[5, 3]`, and `[2, 3]`, showing how
the final chunk can contain fewer rows than the configured chunk size.

## HDF5 installation outside the system paths

Point both pkg-config and the linker at the same HDF5 installation. On Linux:

```sh
export PKG_CONFIG_PATH=/path/to/hdf5/lib/pkgconfig
export LIBRARY_PATH=/path/to/hdf5/lib
export LD_LIBRARY_PATH=/path/to/hdf5/lib
crystal run examples/01_typed_io.cr
```

Check the selected version with `pkg-config --modversion hdf5`. HDF5 1.x is
rejected at compile time. Runtime library paths depend on the platform; the
`LD_LIBRARY_PATH` setting above applies to Linux.

To run all examples:

```sh
for example in examples/*.cr; do
  crystal run "$example" || exit "$?"
done
```

## API conventions used here

- Numeric matrices are flat arrays in row-major order with an explicit `shape:`.
  Nested numeric arrays mean variable-length elements (example 11).
- `read` always returns a flat array; `read_scalar` returns one value, and
  `read_null` returns an `Empty(T)` marker (example 10).
- Integer selections drop an axis. Use `selection.result_shape(dataset.shape)`
  to obtain the selected shape without changing the flat return type (example 04).
- The default cast policy delegates conversions to HDF5. `Casting::Safe` checks
  array datatype ranges and scalar values before conversion (example 06).
- `each_block` bounds the fixed-length read representation. Variable-length
  strings and numeric arrays use `each_chunk` instead (examples 09 and 11).
- Block APIs close supplied handles. Close datatype and reference handles obtained
  explicitly; file closure also invalidates remaining child handles (examples 06
  and 11).
