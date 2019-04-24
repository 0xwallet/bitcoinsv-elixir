defmodule Bitcoin.Crypto do
  use ExUnit.Case

  alias Bitcoin.Crypto
  alias Bitcoin.Base58Check
  alias Bitcoin.Util

  @priv "1AEB4829D9E92290EF35A3812B363B0CA87DFDA2B628060648339E9452BC923A" |> Binary.from_hex()

  @base58_priv (<<0x80>> <> @priv) |> Base58Check.encode()



  test "sign" do
    Util.print @base58_priv
  end

end
