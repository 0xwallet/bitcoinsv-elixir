defmodule Bitcoin.Cli do
  alias Bitcoin.Tx.TxMaker
  alias Bitcoin.Key

  # hex_string -> wallet
  def new_wallet(hex_private_key) do
    bn_private_key = hex2bin(hex_private_key)
    bn_public_key = Key.privkey_to_pubkey(bn_private_key)
    address = Key.Public.to_address(bn_public_key)
    %{
      hex_private_key: hex_private_key,
      bn_private_key: bn_private_key,
      bn_public_key: bn_public_key,
      address: address,
      balacne: nil,
      utxos: []
    }
  end

  # wallet -> integer
  def get_balance(wallet) do
    utxos = TxMaker.Resource.utxos(wallet.address)
    sum_of_utxos = get_sum_of_utxos(utxos)
    %{
      wallet |
      balance: sum_of_utxos,
      utxos: utxos,
      utxo_count: length(utxos)
    }
  end

  defp get_sum_of_utxos(utxos) do
    Enum.reduce(utxos, 0, fn x, acc -> acc + x.amount end)
  end

  # wallet, [{address, satoshis}] -> rpc_txid
  def transfer(wallet, outputs, fee_per_byte \\ 1) do
    sum_of_outputs = Enum.reduce(outputs, 0, fn {_, value}, acc -> acc + value end)

    if sum_of_outputs >= wallet.balance do
      raise("insufficient balance")
    end

    output_count = length(outputs)
    {spendings, outputs} = case get_enough_utxos(wallet.utxos, sum_of_outputs, output_count, [], 0, fee_per_byte) do
      {:no_change, spendings} ->
        {spendings, outputs}
      {:change, change, spendings} ->
        outputs = outputs ++ [{wallet.address, change}]
        {spendings, outputs}
    end

    TxMaker.create_p2pkh_transaction(wallet.bn_private_key, spendings, outputs)
  end

  defp get_enough_utxos(utxos, sum_of_outputs, output_count, spendings, spending_count, fee_per_byte) do
    fee_with_change = get_fee(spending_count, output_count + 1, fee_per_byte)
    # fee_without_change = get_fee(spending_count, output_count)
    sum_of_spendings = get_sum_of_utxos(spendings)

    cond do

      # # no need change, change value less than dust limit
      # sum_of_spendings >= fee_without_change + sum_of_outputs and sum_of_spendings - (fee_without_change + sum_of_outputs) <= 546 ->
      #   {:no_change, spendings}

      sum_of_spendings <= (fee_with_change + sum_of_outputs) and utxos == [] ->
        {:error, "insufficient balance"}

      sum_of_spendings <= fee_with_change + sum_of_outputs ->
        get_enough_utxos(tl(utxos), sum_of_outputs, output_count, [hd(utxos) | spendings], spending_count + 1, fee_per_byte)

      true ->
        change = sum_of_spendings - (fee_with_change + sum_of_outputs)
        if change >= 546 do
          {:change, change, spendings}
        else
          {:no_change, spendings}
        end

    end
  end

  defp hex2bin(x), do: Binary.from_hex(x)

  defp get_fee(n_in, n_out, fee_per_byte) do
    TxMaker.estimate_tx_fee(n_in, n_out, fee_per_byte, true)
  end
end
