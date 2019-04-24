defmodule Bitcoin.Key do
  alias Bitcoin.Base58Check

  def privkey_to_pubkey(priv) do
    {publickey, _priv} = :crypto.generate_key(:ecdh, :secp256k1, priv)
    compress(publickey)
  end

  def compress(<<_prefix::size(8), x_coordinate::size(256), y_coordinate::size(256)>>) do
    prefix = case rem(y_coordinate, 2) do
      0 -> 0x02
      _ -> 0x03
    end
    <<prefix::size(8), x_coordinate::size(256)>>
  end

  def privkey_to_wif(priv) do
    # mainnet
    (<<0x80>> <> priv) |> Base58Check.encode()
  end
end
