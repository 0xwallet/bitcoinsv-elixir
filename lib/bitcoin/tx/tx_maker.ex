defmodule Bitcoin.Tx.TxMaker do

  alias Bitcoin.Protocol.Messages
  alias Bitcoin.Protocol.Types.TxOutput
  alias Bitcoin.Protocol.Types.TxInput
  alias Bitcoin.Protocol.Types.Outpoint
  alias Bitcoin.Base58Check
  alias Bitcoin.Tx.Utxo
  alias Bitcoin.Script

  @sequence 4294967295

  def get_utxos_from_bitindex(addr) do
    {:ok, data} = SvApi.Bitindex.utxos(addr)
    utxos = for d <- data do
      %Utxo{
        hash: d["txid"] |> Binary.from_hex() |> Binary.reverse(),
        index: d["vout"],
        value: d["value"],
        script_pubkey: d["scriptPubKey"]
      }
    end
    utxos
  end

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
    outputs_value = for {_, v} <- avps do
      v
    end |> Enum.sum()

    utxos_value = for %{value: v} <- utxos do
      v
    end |> Enum.sum()

    if outputs_value >= utxos_value do
      raise("Balance not enough.")
    end

    %Messages.Tx{version: 1, lock_time: 0}
    |> add_outputs(avps)
    |> add_inputs(utxos)
  end

  defp add_outputs(tx, avps) do
    outputs = for {addr, value} <- avps do
      %TxOutput{
        value: value,
        pk_script: address_to_pk_script(addr)
      }
    end
    %{tx | outputs: outputs}
  end

  def address_to_pk_script(addr) do
    pkhash = address_to_public_key_hash(addr)
    [:OP_DUP, :OP_HASH160, pkhash, :OP_EQUALVERIFY, :OP_CHECKSIG] |> Script.to_binary()
  end

  defp add_inputs(tx, utxos) do
    inputs = for u <- utxos do
      utxo_to_input(u)
    end
    %{tx | inputs: inputs}
  end

  def utxo_to_input(u = %Utxo{}) do
    outpoint = %Outpoint{
      hash: u.hash,
      index: u.vout
    }
    %TxInput{
      previous_output: outpoint,
      sequence: @sequence
    }
  end

  def address_to_public_key_hash(addr) do
    {:ok, <<_prefix::bytes-size(1), pubkeyhash::binary>>} = Base58Check.decode(addr)
    pubkeyhash
  end
end
