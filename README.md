# PyCUDA Docker Image Generator

This script facilitates the creation of Docker images combining Python and CUDA. It is specifically designed to craft Docker images based on Debian OS with user-specified versions of Python and CUDA, optionally incorporating Python dependencies defined in a `requirements.txt` file.

## Installation

```bash
wget https://github.com/dimak98/Python-CUDA-Docker-Generator/raw/main/pycuda.sh
chmod +x ./pycuda.sh
./pycuda.sh --help
```

## Usage

``bash
Usage: ./pycuda.sh --python PYTHON_VERSION --cuda CUDA_VERSION [--requirements REQUIREMENTS_PATH]

Options:
  -h, --help                Show this help message and exit.
  -p, --python VERSION      Specify the Python version to use.
  -c, --cuda VERSION        Specify the CUDA version to use.
  -r, --requirements PATH   Specify the path to a requirements.txt file for Python packages.
```