defmodule Bitcoin.Tx.TxMaker do

  alias Bitcoin.Protocol.Messages
  alias Bitcoin.Protocol.Types.TxOutput
  alias Bitcoin.Base58Check

  @doc """
  params example: %{
    privkey: <<my binary private key>>,
    address: "my address"
    utxos: [%Bitcoin.Tx.Utxo{}],
    addr_value_pairs: [
      {"1QL7Qbed9X4qfs89bxyKwqwCV9fioGW4Hg", 1000 #satoshi},
    ]
  }
  """
  def make(%{privkey: s, address: addr, utxos: utxos, addr_value_pairs: avps}) do
    %Messages.Tx{}
    |> add_outputs(avps)
  end

  def add_outputs(tx, avps) do
    for {addr, value} <- avps do
      %TxOutput{
        value: value,
        pk_script: address_to_public_key_hash(addr)
      }
    end
  end

  def address_to_public_key_hash(addr) do
    {:ok, <<_prefix::bytes-size(1), pubkeyhash::binary>>} = Base58Check.decode(addr)
    pubkeyhash
  end
end
