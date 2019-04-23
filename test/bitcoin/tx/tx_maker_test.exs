defmodule Bitocin.Tx.TxMakerTest do
  alias Bitcoin.Tx.TxMaker

  use ExUnit.Case

  test "address_to_public_key_hash" do
    pubkeyhash = Binary.from_hex("3c3fa3d4adcaf8f52d5b1843975e122548269937")
    addr = "16VZnHwRhwrExfeHFHGjwrgEMq8VcYPs9r"

    assert pubkeyhash == TxMaker.address_to_public_key_hash(addr)
  end
end
