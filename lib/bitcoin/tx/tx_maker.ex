defmodule Bitcoin.Tx.TxMaker do

  alias Bitcoin.Protocol.Messages
  alias Bitcoin.Protocol.Types.TxOutput
  alias Bitcoin.Protocol.Types.TxInput
  alias Bitcoin.Protocol.Types.Outpoint
  alias Bitcoin.Base58Check
  alias Bitcoin.Tx.Utxo
  alias Bitcoin.Script
  alias Bitcoin.Protocol.Types.VarInteger
  alias Bitcoin.Util


  defmodule Resource do
    def utxos(addr) do
      {:ok, data} = SvApi.Bitindex.utxos(addr)
      utxos = for d <- data do
        %Utxo{
          hash: d["txid"] |> Util.from_rpc_hex(),
          index: d["vout"],
          value: d["value"],
          script_pubkey: d["scriptPubKey"] |> Binary.from_hex()
        }
      end
      utxos
    end
  end


  use GenServer

  def new(privkey, from, to, value) do
    caller = self()
    GenServer.start(__MODULE__, %{
      caller: caller,
      privkey: privkey,
      from: from,
      to: to,
      value: value
    })
  end

  def init(params) do
    state = %{
      fee_per_byte: 1,
      swquence: 0xffffffff,
      utxos: [],
      balance: 0,
      resource: Resource,
    } |> Map.merge(params)

    send(self(), :get_utxos)
    {:ok, state}
  end

  def handle_info(:get_utxos, state) do
    utxos = state.resource.utxos(state.from)

    balance = sum_of_utxos(utxos)

    send(state.caller, {:balance, balance})
    send(self(), :make_tx)

    {:noreply, %{state | utxos: utxos, balance: balance}}
  end

  def handle_info(:make_tx, state) do

  end

  defp sum_of_utxos(list) do
    for %{value: v} <- list do
      v
    end |> Enum.sum()
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

    output_count = length(avps)

    spending_utxos = get_enough_utxos(utxos, outputs_value)

    %Messages.Tx{version: 1, lock_time: 0}
    |> add_outputs(avps)
    |> add_inputs(utxos)
  end

  def get_enough_utxos(utxos, value) do
    utxos
    |> Enum.sort(&(&1.value >= &2.value))
    |> Enum.reduce_while({0, []}, fn x, {sum, us} ->
      if sum > value, do: {:halt, {sum, us}}, else: {:cont, {sum + x.value, [x | us]} }
    end)
    |> elem(1)
    |> check_if_enough(value)
  end

  defp check_if_enough(utxos, value) do
    if sum_of_utxos(utxos) > value do
      utxos
    else
      raise("Balance not enough.")
    end
  end

  def estimated_size(n_in, n_out) do
    4 +  # version
    n_in * 148  # input compressed
    + byte_size(VarInteger.serialize(n_in))
    + n_out * 34  # excluding op_return outputs, dealt with separately
    + byte_size(VarInteger.serialize(n_out))
    + 4  # time lock
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
