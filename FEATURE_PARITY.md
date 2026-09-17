# ruby-hdf5 feature mapping

Comparison baseline: red-data-tools/ruby-hdf5 commit `98294e3`.

Supported environment: Crystal 1.20+ and HDF5 2.0+. HDF5 1.x is unsupported.

| ruby-hdf5 capability | Crystal interface and behavior |
| --- | --- |
| File modes r, r+, w, x, a; flush and block cleanup | Symbol modes `:r`, `:r_plus`/`:rw`, `:w`, `:x`/`:excl`, `:a`; `flush`; block APIs |
| Groups and nested paths | `create_group`, `open_group`, `require_group`; creation enables intermediate groups |
| Lookup and hierarchy management | `[] : Group \| Dataset`, `open_object`, `open_dataset`, `keys`, `each`, `exists?`, `delete`, `move` |
| Hard, soft and external link inspection | `link`, `soft_link`, `external_link`; `link_info : HardLink \| SoftLink \| ExternalLink`, including dangling links |
| Numo multidimensional arrays | Flat `Array(T)`/`Slice(T)` with explicit row-major `shape:`; no external numerical array dependency |
| Inferred and explicit dataset dtype | Inferred `TypedDataset(T)` or explicit `create_dataset(path, T, data)`; open with `dataset(path, T)` |
| Numeric widths, signs and byte orders | Int8–Int64, UInt8–UInt64, Float32/64; native memory conversion reads either byte order |
| Bool and complex64/128 | `Bool`, `HDF5::Complex32`, standard `Complex`; h5py-compatible enum/compound storage |
| UTF-8 / ASCII variable strings | `String`, `encoding:`, `StringType.variable`; NUL and encoding validation |
| Scalar, empty and Null data | `read_scalar`, flat `read`, `Empty(T)` and `read_null`; explicit `space_class`, `scalar?`, `null?` |
| Shape, ndim, size and dtype metadata | `shape`, `rank`, `size`, `datatype`; byte order, precision, offset, string and compound metadata |
| Chunks, maximum shape and fill value | `chunk`, `max_shape`, typed `fill_value`; untyped `fill_value(T)` |
| Whole and selected reads/writes | `read`, `write`, `dataset[selection]`, `dataset[selection] = values`; strings included |
| Python-style slices | `HDF5.s[...]`, `HDF5.slice(range, step:)`; negatives, open ranges, omitted axes, positive strides; `Selection#result_shape` |
| Nested / flattened `read_array` output | Always flat `Array(T)`; inspect shape separately to avoid return types depending on runtime rank |
| Scalar broadcasting | `write(value, selection: ...)` and scalar creation with shape; bounded reusable working buffer |
| Read into an existing array | `read_into(Slice(T), selection: ...)`, with exact selected element count validation |
| Safe and unsafe casts | `Casting::Safe` opt-in; `Casting::Unsafe` default, as requested for Crystal |
| Chunking, gzip, shuffle, Fletcher32 | Creation keywords or `DatasetCreateOptions`; filter and configuration checks |
| Automatic chunks | `chunk: :auto`; 256 KiB target; automatic for filters/extendible storage |
| Resize and append | `resize`, `append(data, shape:, axis:)`; maximum shape validation and extent rollback |
| Bounded block iteration | `each_block(max_bytes:)`; untyped datasets also take T; variable-length payloads rejected |
| Physical chunk region iteration | `each_chunk`; partial trailing chunks and variable-length elements supported |
| Scalar and shaped attributes | `attrs.get`, `get_array`, `get_null`; `create(..., shape:)`, explicit storage type overloads |
| Attribute creation, replacement and modification | `create`, `write`/`[]=`, `modify`, `delete`; staged replacement and type/shape-preserving modification |
| Context closure and native failures | Shared file context, serialized native access, closed-object guards, checked status and exception-preserving cleanup |
| Runtime Ruby library discovery | Compile-time HDF5 linking via pkg-config/system linker; configured using standard linker environment variables |

Crystal additionally retains fixed-length strings, object references, variable-length numeric elements, datatype introspection and explicit block hyperslabs. `Reference#dup` uses H5Rcopy; references are destroyed before closing their associated file.

ruby-hdf5's documented unsupported features remain out of scope: fancy indexing, masks, negative strides, general broadcasting, SWMR, MPI and VDS creation. Generic compound/enum data models are not added; Bool and complex use well-defined compatible layouts.
