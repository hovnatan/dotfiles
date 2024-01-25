from sympy import nonlinsolve, symbols

x, y, z = symbols("x y z", real=True)

nonlinsolve([x / y - (x + 3000) / 2676, x / y - (x + 8000) / 3050], [x, y])
