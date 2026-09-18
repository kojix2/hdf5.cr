# hdf5.cr

[![CI](https://github.com/kojix2/hdf5.cr/actions/workflows/ci.yml/badge.svg)](https://github.com/kojix2/hdf5.cr/actions/workflows/ci.yml)
[![Lines of Code](https://img.shields.io/endpoint?url=https%3A%2F%2Ftokei.kojix2.net%2Fbadge%2Fgithub%2Fkojix2%2Fhdf5.cr%2Flines)](https://tokei.kojix2.net/github/kojix2/hdf5.cr)
![Static Badge](https://img.shields.io/badge/PURE-Vibe_Coding-magenta)

HDF5 bindings for Crystal.

## Requirements and installation

Crystal **1.20+**, HDF5 **2.0+**, and `pkg-config` are required. HDF5 1.x is
unsupported. Install HDF5 with your system package manager, then add:

```yaml
dependencies:
  hdf5:
    github: kojix2/hdf5.cr
```

Run `shards install`. HDF5 is linked at compile time. For a nonstandard HDF5
installation, set `PKG_CONFIG_PATH` and `LIBRARY_PATH`; on Linux also set
`LD_LIBRARY_PATH` to the library directory.

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
    p signal.shape                         # [2, 2]
    p signal.read(HDF5.s[1, HDF5.all])     # [3.0, 4.0]
    p signal.attrs.get("unit", String)    # "a.u."
  end
end
```

Datasets use flat, row-major `Array(T)` or `Slice(T)` values; specify `shape:`
for multidimensional data. `create_dataset` infers the element type, while
`dataset(path, T)` opens an existing dataset with its Crystal type.

## Examples

The [runnable examples](examples/README.md) are the complete usage guide.

matrix and unsupported features.

## Development

```sh
crystal spec
# Enable the bidirectional Python checks with an environment containing h5py and numpy:
H5PY_PYTHON=/path/to/python crystal spec
crystal tool format --check src spec examples
```

## License

MIT
