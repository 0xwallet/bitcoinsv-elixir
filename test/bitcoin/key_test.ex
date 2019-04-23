defmodule Bitcoin.KeyTest do
  use ExUnit.Case
  alias Bitcoin.Key

  test "privkey to pubkey" do
    privkey = "c28a9f80738f770d527803a566cf6fc3edf6cea586c4fc4a5223a5ad797e1ac3" |> Binary.from_hex()
    pubkey = "033d5c2875c9bd116875a71a5db64cffcb13396b163d039b1d9327824891804334" |> Binary.from_hex()
    pubkey1 = Key.privkey_to_pubkey(privkey)
    assert pubkey1 == pubkey
  end
end
