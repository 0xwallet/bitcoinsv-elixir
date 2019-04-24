defmodule Bitcoin.Crypto do
  @moduledoc """
  Currently just wrappers around erlang's :crypto for easy piping.
  """
  alias Bitcoin.DERSig

  def ripemd160(bin), do: :crypto.hash(:ripemd160, bin)
  def sha1(bin), do: :crypto.hash(:sha, bin)
  def sha256(bin), do: :crypto.hash(:sha256, bin)

  @doc """
  auto do sha256 hash before sign.
  """
  def sign(priv, data) do
    :crypto.sign(:ecdsa, :sha256, data, [priv, :secp256k1])
    |> DERSig.normalize()
  end

  @doc """
  auto do sha256 hash before verify.
  """
  def verify(sig, data, pubkey) do
    :crypto.verify(:ecdsa, :sha256, data, sig, [pubkey, :secp256k1])
  end
end
