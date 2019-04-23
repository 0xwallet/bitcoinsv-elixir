defmodule Bitocin.Tx.TxMakerTest do
  alias Bitcoin.Tx.TxMaker

  use ExUnit.Case

  test "address_to_public_key_hash" do
    pubkeyhash = Binary.from_hex("3c3fa3d4adcaf8f52d5b1843975e122548269937")
    addr = "16VZnHwRhwrExfeHFHGjwrgEMq8VcYPs9r"

    assert pubkeyhash == TxMaker.address_to_public_key_hash(addr)
  end

  test "address_to_pk_script" do
    addr = "18WqBk5qDRXuwmphgg2oX5SpEWpV8uH1gk"
    pks = TxMaker.address_to_pk_script(addr)
    assert pks == Binary.from_hex("76a914526d2a97902d5dc95b6060a54dbcb74a587c818c88ac")
  end
end
