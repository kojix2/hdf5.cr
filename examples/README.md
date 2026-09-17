# Examples

Run from the repository root with Crystal and HDF5 installed:

```sh
crystal run examples/01_typed_io.cr
crystal run examples/02_append_and_blocks.cr
crystal run examples/03_types_and_attributes.cr
```

Each example uses a temporary HDF5 file and removes it after completion. Set your normal HDF5 linker/runtime environment if needed.
