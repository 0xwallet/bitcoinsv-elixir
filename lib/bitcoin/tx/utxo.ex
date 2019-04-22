defmodule Bitcoin.Tx.Utxo do
  defstruct [
    :address,
    :amount,
    :confirmations,
    :height,
    :scriptPubKey,
    :txid,
    :value,
    :vout # output index
  ]
end
