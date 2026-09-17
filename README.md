# hdf5.cr

[![CI](https://github.com/kojix2/hdf5.cr/actions/workflows/ci.yml/badge.svg)](https://github.com/kojix2/hdf5.cr/actions/workflows/ci.yml)
[![Lines of Code](https://img.shields.io/endpoint?url=https%3A%2F%2Ftokei.kojix2.net%2Fbadge%2Fgithub%2Fkojix2%2Fhdf5.cr%2Flines)](https://tokei.kojix2.net/github/kojix2/hdf5.cr)
![Static Badge](https://img.shields.io/badge/PURE-Vibe_Coding-magenta)

HDF5 bindings for Crystal, with typed datasets, partial I/O and extensible storage.

## Requirements and installation

Crystal **1.20+**, HDF5 **2.0+**, and `pkg-config` are required. HDF5 1.x is unsupported and rejected at compile time. Install HDF5 with your system package manager, then add:

```yaml
dependencies:
  hdf5:
    github: kojix2/hdf5.cr
```

Run `shards install`. HDF5 is linked at compile time. For a nonstandard installation, configure `PKG_CONFIG_PATH` and `LIBRARY_PATH`; on Linux, also set `LD_LIBRARY_PATH` to its library directory at runtime. Ruby's runtime `HDF5_LIB_PATH` setting is not used.

## Write and read

```crystal
require "hdf5"

HDF5.open("data.h5", :w) do |file|
  file.create_dataset("measurements/signal", [1.0, 2.0, 3.0, 4.0], shape: {2, 2}) do |signal|
    signal.attrs["unit"] = "a.u."
  end
  file.attrs["title"] = "example"
end

HDF5.open("data.h5") do |file|
  file.dataset("measurements/signal", Float64) do |signal|
    p signal.shape                                  # [2, 2]
    p signal.read                                   # [1.0, 2.0, 3.0, 4.0]
    p signal.read(HDF5.s[1, HDF5.all])                # [3.0, 4.0]
    p signal.read_scalar(HDF5.s[0, 1])                # 2.0
    p signal.attrs.get("unit", String)                # "a.u."
  end
end
```

`create_dataset` infers the Crystal element type, returning `TypedDataset(T)`. `dataset(path, T)` supplies the type when opening an existing dataset. `open_dataset` returns an untyped `Dataset`; read it with `read(T)` or `read_scalar(T)`. `file[path]` returns `Group | Dataset`, so narrow that union before using object-specific operations.

Data is always flat and in row-major order. Specify `shape:` for multidimensional data. `read` always returns `Array(T)`, including a one-element array for a scalar. Shape information comes from `dataset.shape` or `selection.result_shape(dataset.shape)`. Nested numeric arrays remain variable-length elements, not rectangular matrices.

You can choose a storage type explicitly: `file.create_dataset("wide", Int64, [1, 2])`. Both `Array(T)` and `Slice(T)` inputs support shape and storage options. Creation from a scalar defaults to shape `[]`; an explicit shape broadcasts that scalar across the dataset.

## Selections and existing buffers

```crystal
selection = HDF5.s[1.., HDF5.slice(0...10, step: 2)]
values = dataset.read(selection)
p selection.result_shape(dataset.shape)
dataset.write(values, selection)
dataset.write(0.0, selection: selection) # scalar broadcast, bounded working buffer

buffer = Slice(Float64).new(values.size, 0.0)
dataset.read_into(buffer, selection: selection)
```

Selectors support integers, negative indices, inclusive/exclusive ranges, open-ended ranges, `HDF5.all` (or `nil`) and positive strides. Omitted axes select the complete axis. Integer indices drop an axis in the result shape. Empty selections return empty arrays and accept empty writes. Out-of-range integers and excess axes raise `IndexError`.

`Selection.hyperslab(start, count, stride: ..., block: ...)` supports non-overlapping block hyperslabs. `dataset[selection]` and `dataset[selection] = values` are shortcuts. String datasets also support partial I/O.

Buffer length and write element counts must match the selected element count. `read_to(Slice(T))` remains an alias of `read_into`. Pointer-based `read_to` and attribute `read_raw`/`write_raw` are low-level unsafe APIs: callers must supply the native representation and sufficient capacity.

## Scalars, Null and special types

```crystal
file.create_dataset("scalar", 1.5).close
file.create_dataset("empty", Float32, shape: {0, 3}).close
file.create_dataset("null", HDF5::Empty(Float32).new).close
file.create_dataset("enabled", [false, true]).close
file.create_dataset("complex128", [Complex.new(1, 2)]).close
file.create_dataset("complex64", [HDF5::Complex32.new(1, 2)]).close
file.create_dataset("labels", ["alpha", "日本語"]).close
file.create_dataset("fixed", ["alpha"], string_type: HDF5::StringType.fixed(8)).close
```

Use `scalar?`, `null?` and `space_class` to distinguish scalar, Null and simple dataspaces. `shape` remains an array: both a scalar and Null have `[]`, while an empty matrix has `[0, 3]`. A Null has zero elements and uses `read_null`, returning `Empty(T)`; regular I/O, resize and append reject it.

Bool uses an enum (`FALSE=0`, `TRUE=1`). Complex values use compound members `r` and `i`. These storage formats are compatible with ruby-hdf5 and h5py. Standard `Complex` has Float64 components; `HDF5::Complex32` has Float32 components and converts explicitly with `.to_c` or `Complex32.new(complex)`.

Strings default to variable-length UTF-8. Use `encoding: :ascii` or an explicit `StringType` for other supported storage. Embedded NUL, invalid UTF-8 and non-ASCII input for ASCII storage are rejected. Fixed-length strings keep the existing truncation and padding behavior by default; `Casting::Safe` rejects input that would be truncated.

Object references and variable-length numeric arrays are supported as before. `Reference#dup` makes an independent native copy. Close references when finished; file closure also destroys references associated with that file.

## Storage, append and iteration

```crystal
file.create_dataset("samples", Float32,
  shape: {0, 2}, max_shape: {nil, 2}, chunk: {256, 2},
  compression: :gzip, compression_level: 6,
  shuffle: true, fletcher32: true, fill_value: 0.0_f32) do |samples|
  samples.append([1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32], shape: {2, 2})
  samples.each_block(max_bytes: 4 * 1024 * 1024) do |selection, values|
    p values.sum
  end
  samples.each_chunk { |selection, values| p selection.result_shape(samples.shape) }
end
```

`chunk: :auto` targets 256 KiB for fixed-length storage. Filters and an extendible maximum shape enable automatic chunking when no explicit chunks are supplied. Zero-sized initial dimensions are supported. `nil` in `max_shape` means unlimited; `HDF5.unlimited` remains accepted.

Inspect stored settings with `chunk`, `max_shape` and typed `fill_value` (or `fill_value(T)` on an untyped Dataset). `datatype` exposes byte order, precision, bit offset, string metadata and compound members. Close returned datatype/dataspace handles when finished.

`resize` checks rank, maximum dimensions and chunked storage. `append` defaults to axis 0; multidimensional appends require their incoming `shape:`. Other axes must match. A failed append restores the original extent; if restoration also fails, the error retains the original write failure as its cause.

`each_block` yields a Selection and an independent flat Array within the requested element-payload byte budget, calculated using the requested Crystal type. Fixed-length string blocks use the stored byte width as an upper bound on each returned string payload. Variable-length strings and numeric arrays cannot provide that byte bound and reject this operation. `each_chunk` works with those types and includes clipped final chunks. For untyped datasets, pass the element type as the first argument. Neither operation holds the native lock while your block runs.

## Attributes and hierarchy

```crystal
attrs = dataset.attrs
attrs.create("scale", Int16, 2)                         # reject existing name
attrs.modify("scale", 4)                               # preserve type and shape
attrs.write("scale", "replacement")                    # create or replace
attrs.create("matrix", [1, 2, 3, 4], shape: {2, 2})
p attrs.get_array("matrix", Int32)
attrs.create("null", HDF5::Empty(Int16).new)
p attrs.get_null("null", Int16)
```

`attrs[name]` returns an Attribute handle; `get` reads a scalar, `get_array` reads a flat array, and `get_null` reads a Null marker. `attrs[name] = value` uses `write`. Replacement is staged through a temporary attribute so failed input validation or writing preserves the original attribute. `modify` preserves the existing datatype and shape; an optional `shape:` is checked against that shape. Creation, replacement and modification return `Nil`.

Containers support `create_group`, `require_group`, `keys`, `each`, `exists?`, `delete`, `move`, hard `link`, `soft_link` and `external_link`. `link_info` returns `HardLink | SoftLink | ExternalLink`, including for dangling links. `require_group` raises `TypeMismatchError` if the existing object is a Dataset.

File modes are `:r`, `:r_plus`/`:rw`, `:w`, `:x`/`:excl` and `:a`. Block APIs close resources automatically. Closing a file closes associated children and metadata; later operations raise `ClosedObjectError`. Close is idempotent, and a native close failure leaves the handle available for retry. Cleanup failures do not replace an exception from a user block.

## Casting and migration

The default `Casting::Unsafe` permits HDF5's available conversions, including narrowing. It does not waive shape or buffer checks. Opt into lossless conversion checks with `casting: HDF5::Casting::Safe`. Array conversion is checked by source/target type; scalar values and fill values are checked for representability. Safe casts keep Bool distinct from numeric coercion. Inputs must have a supported homogeneous Crystal element type.

Existing `read`/`write`, `HDF5.s`, `chunk`, `max_shape`, Symbol file modes and typed datasets remain available. String selections and checked Slice reads now work. Attribute scalar `read` rejects arrays; use `read_array` instead. File closure now invalidates associated child handles. Earlier README examples using `write_dataset`, `read_dataset`, `set_attribute` and `get_attribute` were obsolete: use `create_dataset`, `dataset(..., T)` and `attrs` as shown above.

See [the ruby-hdf5 feature mapping](FEATURE_PARITY.md) and [runnable examples](examples/README.md).

## Development

```sh
crystal spec
# Enable the bidirectional Python checks with an environment containing h5py and numpy:
H5PY_PYTHON=/path/to/python crystal spec
crystal tool format --check src spec examples
```

The reference lifecycle tests build a small Crystal worker and check explicit close, GC and process exit in separate processes. CI enables h5py tests on Linux and macOS. The local comparison checkout of ruby-hdf5 is not a build or test dependency.

Fancy indexing, masks, negative slice steps, general broadcasting beyond scalar fill, SWMR, MPI and VDS creation are unsupported.

## License

MIT
