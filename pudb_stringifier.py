__copyright__ = """
Copyright (C) 2009-2017 Andreas Kloeckner
Copyright (C) 2014-2017 Aaron Meurer
"""

__license__ = """
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
"""

try:
    import numpy
    HAVE_NUMPY = 1
except ImportError:
    HAVE_NUMPY = 0

try:
    import torch
    HAVE_PYTORCH = 1
except ImportError:
    HAVE_PYTORCH = 0

from pathlib import Path


class WatchEvalError(object):
    def __str__(self):
        return "<error>"


def get_str_safe_types():
    import types

    return tuple(
        getattr(types, s)
        for s in "BuiltinFunctionType BuiltinMethodType  ClassType "
        "CodeType FileType FrameType FunctionType GetSetDescriptorType "
        "LambdaType MemberDescriptorType MethodType ModuleType "
        "SliceType TypeType TracebackType UnboundMethodType XRangeType".split()
        if hasattr(types, s)
    ) + (WatchEvalError, )


STR_SAFE_TYPES = get_str_safe_types()


def pudb_stringifier(value):
    if HAVE_NUMPY and isinstance(value, numpy.ndarray):
        return ("ndarray %s %s") % (value.dtype, value.shape)
    elif HAVE_NUMPY and numpy.isscalar(value):
        return ("%s") % value
    elif HAVE_PYTORCH and isinstance(value, torch.Tensor):
        dtype = str(value.dtype)[6:]
        shape = tuple(value.size())
        if shape:
            return ("tTensor %s %s") % (dtype, shape)
        else:
            return ("tTensor %s %s %s") % (dtype, shape, value.item())
    elif isinstance(value, Path):
        return ("Path %s") % value

    elif isinstance(value, STR_SAFE_TYPES):
        try:
            return (value)
        except Exception:
            pass

    elif hasattr(type(value), "safely_stringify_for_pudb"):
        try:
            # (E.g.) Mock objects will pretend to have this
            # and return nonsense.
            result = value.safely_stringify_for_pudb()
        except Exception:
            pass
        else:
            return result

    elif type(value) in [set, frozenset, list, tuple, dict]:
        return ("%s (%s)") % (type(value).__name__, len(value))

    return type(value).__name__
