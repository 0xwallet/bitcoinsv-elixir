defmodule Bitcoin.KeyTest do
  use ExUnit.Case
  alias Bitcoin.Key

  test "privkey to pubkey" do
    privkey = "c28a9f80738f770d527803a566cf6fc3edf6cea586c4fc4a5223a5ad797e1ac3" |> Binary.from_hex()
    pubkey = "033d5c2875c9bd116875a71a5db64cffcb13396b163d039b1d9327824891804334" |> Binary.from_hex()
    pubkey1 = Key.privkey_to_pubkey(privkey)
    assert pubkey1 == pubkey

    privkey2 = "1AEB4829D9E92290EF35A3812B363B0CA87DFDA2B628060648339E9452BC923A" |> Binary.from_hex()
    address2 = "1EMHJsiXjZmffBUWevGS5mWdoacmpt8vdH"
    pubkey2 = Key.privkey_to_pubkey(privkey2)
    assert address2 == Bitcoin.Key.Public.to_address(pubkey2)
  end

  test "privkey to wif" do
    p = "1AEB4829D9E92290EF35A3812B363B0CA87DFDA2B628060648339E9452BC923A" |> Binary.from_hex()
    wif = Key.privkey_to_wif(p)

    assert "Kx83ACqTy1EVasPzY9nPecfhbRwnqS1Gpjw2nUqxkD6ATc8dBEeW" == wif
  end
end
