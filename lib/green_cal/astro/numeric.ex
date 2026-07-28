defmodule GreenCal.Astro.Numeric do
  # Shared numeric primitives — kept in one place so the polynomial
  # evaluator and the root finder cannot drift apart between modules.
  @moduledoc false

  @doc """
  Evaluates a polynomial `c0 + c1·x + c2·x² + …` (Horner form).
  """
  @spec poly(number(), [number()]) :: float()
  def poly(x, coefs) do
    coefs |> Enum.reverse() |> Enum.reduce(0.0, fn c, acc -> acc * x + c end)
  end

  @doc """
  Finds a zero of `f` in `[a, b]` by bisection, assuming exactly one sign
  change in the bracket. `tol` is the bracket width to stop at, in the
  same unit as `a`/`b`.
  """
  @spec bisect_zero((float() -> float()), float(), float(), float()) :: float()
  def bisect_zero(f, a, b, tol \\ 1.0e-7) do
    do_bisect(f, a, b, f.(a), tol)
  end

  defp do_bisect(f, a, b, fa, tol) when b - a > tol do
    mid = (a + b) / 2.0
    fm = f.(mid)

    if same_sign?(fa, fm),
      do: do_bisect(f, mid, b, fm, tol),
      else: do_bisect(f, a, mid, fa, tol)
  end

  defp do_bisect(_f, a, b, _fa, _tol), do: (a + b) / 2.0

  defp same_sign?(x, y), do: (x < 0.0 and y < 0.0) or (x >= 0.0 and y >= 0.0)
end
