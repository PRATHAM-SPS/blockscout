defmodule BlockScoutWeb.AddressView do
  use BlockScoutWeb, :view

  require Logger

  alias BlockScoutWeb.{AccessHelpers, LayoutView}
  alias Explorer.{Chain, CustomContractsHelpers, Repo}

  alias Explorer.Chain.{
    Address,
    BridgedToken,
    Hash,
    InternalTransaction,
    SmartContract,
    Token,
    TokenTransfer,
    Transaction,
    Wei
  }

  alias Explorer.Chain.Block.Reward
  alias Explorer.ExchangeRates.Token, as: TokenExchangeRate
  alias Explorer.SmartContract.{Helper, Writer}
  alias Poison.Parser

  @dialyzer :no_match

  @tabs [
    "coin-balances",
    "contracts",
    "decompiled-contracts",
    "internal-transactions",
    "token-transfers",
    "read-contract",
    "read-proxy",
    "write-contract",
    "write-proxy",
    "tokens",
    "transactions",
    "validations"
  ]

  def address_partial_selector(struct_to_render_from, direction, current_address, truncate \\ false)

  def address_partial_selector(%Address{} = address, _, current_address, truncate) do
    matching_address_check(current_address, address, contract?(address), truncate)
  end

  def address_partial_selector(
        %InternalTransaction{to_address_hash: nil, created_contract_address_hash: nil},
        :to,
        _current_address,
        _truncate
      ) do
    gettext("Contract Address Pending")
  end

  def address_partial_selector(
        %InternalTransaction{to_address: nil, created_contract_address: contract_address},
        :to,
        current_address,
        truncate
      ) do
    matching_address_check(current_address, contract_address, true, truncate)
  end

  def address_partial_selector(%InternalTransaction{to_address: address}, :to, current_address, truncate) do
    matching_address_check(current_address, address, contract?(address), truncate)
  end

  def address_partial_selector(%InternalTransaction{from_address: address}, :from, current_address, truncate) do
    matching_address_check(current_address, address, contract?(address), truncate)
  end

  def address_partial_selector(%TokenTransfer{to_address: address}, :to, current_address, truncate) do
    matching_address_check(current_address, address, contract?(address), truncate)
  end

  def address_partial_selector(%TokenTransfer{from_address: address}, :from, current_address, truncate) do
    matching_address_check(current_address, address, contract?(address), truncate)
  end

  def address_partial_selector(
        %Transaction{to_address_hash: nil, created_contract_address_hash: nil},
        :to,
        _current_address,
        _truncate
      ) do
    gettext("Contract Address Pending")
  end

  def address_partial_selector(
        %Transaction{to_address: nil, created_contract_address: contract_address},
        :to,
        current_address,
        truncate
      ) do
    matching_address_check(current_address, contract_address, true, truncate)
  end

  def address_partial_selector(%Transaction{to_address: address}, :to, current_address, truncate) do
    matching_address_check(current_address, address, contract?(address), truncate)
  end

  def address_partial_selector(%Transaction{from_address: address}, :from, current_address, truncate) do
    matching_address_check(current_address, address, contract?(address), truncate)
  end

  def address_partial_selector(%Reward{address: address}, _, current_address, truncate) do
    matching_address_check(current_address, address, false, truncate)
  end

  def address_title(%Address{} = address) do
    if contract?(address) do
      gettext("Contract Address")
    else
      gettext("Address")
    end
  end

  @doc """
  Returns a formatted address balance and includes the unit.
  """
  def balance(%Address{fetched_coin_balance: nil}), do: ""

  def balance(%Address{fetched_coin_balance: balance}) do
    format_wei_value(balance, :ether)
  end

  def balance_percentage_enabled?(total_supply) do
    Application.get_env(:block_scout_web, :show_percentage) && total_supply > 0
  end

  def balance_percentage(_, nil), do: ""

  def balance_percentage(
        %Address{
          hash: %Explorer.Chain.Hash{
            byte_count: 20,
            bytes: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
          }
        },
        _
      ),
      do: ""

  def balance_percentage(%Address{fetched_coin_balance: balance}, total_supply) do
    if Decimal.cmp(total_supply, 0) == :gt do
      balance
      |> Wei.to(:ether)
      |> Decimal.div(Decimal.new(total_supply))
      |> Decimal.mult(100)
      |> Decimal.round(4)
      |> Decimal.to_string(:normal)
      |> Kernel.<>("% #{gettext("Market Cap")}")
    else
      balance
      |> Wei.to(:ether)
      |> Decimal.to_string(:normal)
    end
  end

  def empty_exchange_rate?(exchange_rate) do
    TokenExchangeRate.null?(exchange_rate)
  end

  def balance_percentage(%Address{fetched_coin_balance: _} = address) do
    balance_percentage(address, Chain.total_supply())
  end

  def balance_block_number(%Address{fetched_coin_balance_block_number: nil}), do: ""

  def balance_block_number(%Address{fetched_coin_balance_block_number: fetched_coin_balance_block_number}) do
    to_string(fetched_coin_balance_block_number)
  end

  def contract?(%Address{contract_code: nil}), do: false

  def contract?(%Address{contract_code: _}), do: true

  def contract?(nil), do: true

  def validator?(val) when val > 0, do: true

  def validator?(_), do: false

  def hash(%Address{hash: hash}) do
    to_string(hash)
  end

  @doc """
  Returns the primary name of an address if available.
  """
  def primary_name(%Address{names: [_ | _] = address_names}) do
    case Enum.find(address_names, &(&1.primary == true)) do
      nil -> nil
      %Address.Name{name: name} -> name
    end
  end

  def primary_name(%Address{names: _}), do: nil

  def primary_validator_metadata(%Address{names: [_ | _] = address_names}) do
    case Enum.find(address_names, &(&1.primary == true)) do
      %Address.Name{
        metadata:
          metadata = %{
            "license_id" => _,
            "address" => _,
            "state" => _,
            "zipcode" => _,
            "expiration_date" => _,
            "created_date" => _
          }
      } ->
        metadata

      _ ->
        nil
    end
  end

  def primary_validator_metadata(%Address{names: _}), do: nil

  def format_datetime_string(unix_date) do
    unix_date
    |> DateTime.from_unix!()
    |> Timex.format!("{M}-{D}-{YYYY}")
  end

  def qr_code(address_hash) do
    address_hash
    |> to_string()
    |> QRCode.to_png()
    |> Base.encode64()
  end

  def smart_contract_verified?(%Address{smart_contract: %{metadata_from_verified_twin: true}}), do: false

  def smart_contract_verified?(%Address{smart_contract: %SmartContract{}}), do: true

  def smart_contract_verified?(%Address{smart_contract: nil}), do: false

  def smart_contract_with_read_only_functions?(%Address{smart_contract: %SmartContract{}} = address) do
    Enum.any?(address.smart_contract.abi, &Helper.queriable_method?(&1))
  end

  def smart_contract_with_read_only_functions?(%Address{smart_contract: nil}), do: false

  def smart_contract_is_proxy?(%Address{smart_contract: %SmartContract{}} = address) do
    Chain.proxy_contract?(address.hash, address.smart_contract.abi)
  end

  def smart_contract_is_proxy?(%Address{smart_contract: nil}), do: false

  def smart_contract_with_write_functions?(%Address{smart_contract: %SmartContract{}} = address) do
    Enum.any?(
      address.smart_contract.abi,
      &Writer.write_function?(&1)
    )
  end

  def smart_contract_with_write_functions?(%Address{smart_contract: nil}), do: false

  def has_decompiled_code?(address) do
    address.has_decompiled_code? ||
      (Ecto.assoc_loaded?(address.decompiled_smart_contracts) && Enum.count(address.decompiled_smart_contracts) > 0)
  end

  def token_title(%Token{name: nil, contract_address_hash: contract_address_hash}) do
    short_hash_left_right(contract_address_hash)
  end

  def token_title(%Token{name: name, symbol: symbol, bridged: bridged, contract_address_hash: contract_address_hash}) do
    bridged_token = Repo.get(BridgedToken, contract_address_hash)

    if bridged do
      Chain.token_display_name_based_on_bridge_destination(name, symbol, bridged_token.foreign_chain_id)
    else
      "#{name} (#{symbol})"
    end
  end

  def trimmed_hash(%Hash{} = hash) do
    string_hash = to_string(hash)
    trimmed_hash(string_hash)
  end

  def trimmed_hash(address) when is_binary(address) do
    "#{String.slice(address, 0..7)}–#{String.slice(address, -6..-1)}"
  end

  def trimmed_hash(_), do: ""

  def trimmed_verify_link(hash) do
    string_hash = to_string(hash)
    "#{String.slice(string_hash, 0..21)}..."
  end

  def transaction_hash(%Address{contracts_creation_internal_transaction: %InternalTransaction{}} = address) do
    address.contracts_creation_internal_transaction.transaction_hash
  end

  def transaction_hash(%Address{contracts_creation_transaction: %Transaction{}} = address) do
    address.contracts_creation_transaction.hash
  end

  def from_address_hash(%Address{contracts_creation_internal_transaction: %InternalTransaction{}} = address) do
    address.contracts_creation_internal_transaction.from_address_hash
  end

  def from_address_hash(%Address{contracts_creation_transaction: %Transaction{}} = address) do
    address.contracts_creation_transaction.from_address_hash
  end

  def from_address_hash(_address), do: nil

  def address_link_to_other_explorer(link, address, full) do
    if full do
      link <> to_string(address)
    else
      trimmed_verify_link(link <> to_string(address))
    end
  end

  defp matching_address_check(%Address{hash: hash} = current_address, %Address{hash: hash}, contract?, truncate) do
    [
      view_module: __MODULE__,
      partial: "_responsive_hash.html",
      address: current_address,
      contract: contract?,
      truncate: truncate,
      use_custom_tooltip: false
    ]
  end

  defp matching_address_check(_current_address, %Address{} = address, contract?, truncate) do
    [
      view_module: __MODULE__,
      partial: "_link.html",
      address: address,
      contract: contract?,
      truncate: truncate,
      use_custom_tooltip: false
    ]
  end

  @doc """
  Get the current tab name/title from the request path and possible tab names.

  The tabs on mobile are represented by a dropdown list, which has a title. This title is the
  currently selected tab name. This function returns that name, properly gettext'ed.

  The list of possible tab names for this page is represented by the attribute @tab.

  Raises error if there is no match, so a developer of a new tab must include it in the list.
  """
  def current_tab_name(request_path) do
    @tabs
    |> Enum.filter(&tab_active?(&1, request_path))
    |> tab_name()
  end

  defp tab_name(["tokens"]), do: gettext("Tokens")
  defp tab_name(["internal-transactions"]), do: gettext("Internal Transactions")
  defp tab_name(["transactions"]), do: gettext("Transactions")
  defp tab_name(["token-transfers"]), do: gettext("Token Transfers")
  defp tab_name(["contracts"]), do: gettext("Code")
  defp tab_name(["decompiled-contracts"]), do: gettext("Decompiled Code")
  defp tab_name(["read-contract"]), do: gettext("Read Contract")
  defp tab_name(["read-proxy"]), do: gettext("Read Proxy")
  defp tab_name(["write-contract"]), do: gettext("Write Contract")
  defp tab_name(["write-proxy"]), do: gettext("Write Proxy")
  defp tab_name(["coin-balances"]), do: gettext("Coin Balance History")
  defp tab_name(["validations"]), do: gettext("Blocks Validated")
  defp tab_name(["logs"]), do: gettext("Logs")

  def short_hash(%Address{hash: hash}) do
    <<
      "0x",
      short_address::binary-size(8),
      _rest::binary
    >> = to_string(hash)

    "0x" <> short_address
  end

  def short_hash_left_right(hash) when not is_nil(hash) do
    case hash do
      "0x" <> rest ->
        shortify_hash_string(rest)

      %Chain.Hash{
        byte_count: _,
        bytes: bytes
      } ->
        shortify_hash_string(Base.encode16(bytes, case: :lower))

      hash ->
        shortify_hash_string(hash)
    end
  end

  def short_hash_left_right(hash) when is_nil(hash), do: ""

  defp shortify_hash_string(hash) do
    <<
      left::binary-size(8),
      _middle::binary-size(26),
      right::binary-size(6)
    >> = to_string(hash)

    "0x" <> left <> "-" <> right
  end

  def short_contract_name(name, max_length) do
    short_string(name, max_length)
  end

  def short_token_id(%Decimal{} = token_id, max_length) do
    token_id
    |> Decimal.to_string()
    |> short_string(max_length)
  end

  def short_token_id(token_id, max_length) do
    short_string(token_id, max_length)
  end

  def short_string(nil, _max_length), do: ""

  def short_string(name, max_length) do
    part_length = Kernel.trunc(max_length / 4)

    if String.length(name) <= max_length,
      do: name,
      else: "#{String.slice(name, 0, max_length - part_length)}..#{String.slice(name, -part_length, part_length)}"
  end

  def address_page_title(address) do
    cond do
      smart_contract_verified?(address) -> "#{address.smart_contract.name} (#{to_string(address)})"
      contract?(address) -> "Contract #{to_string(address)}"
      true -> "#{to_string(address)}"
    end
  end

  def smart_contract_is_gnosis_safe_proxy?(%Address{smart_contract: %SmartContract{}} = address) do
    address.smart_contract.name == "GnosisSafeProxy" && Chain.gnosis_safe_contract?(address.smart_contract.abi)
  end

  def smart_contract_is_gnosis_safe_proxy?(_address), do: false

  def is_faucet?(nil), do: false

  def is_faucet?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    address_hash_str == String.downcase(System.get_env("FAUCET_ADDRESS", ""))
  end

  def is_random_aura?(nil), do: false

  def is_random_aura?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    address_hash_str == String.downcase(System.get_env("RANDOM_AURA_CONTRACT", ""))
  end

  def is_omni_bridge?(nil), do: false

  def is_omni_bridge?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)

    address_hash_str == String.downcase(System.get_env("ETH_OMNI_BRIDGE_MEDIATOR", "")) ||
      address_hash_str == String.downcase(System.get_env("BSC_OMNI_BRIDGE_MEDIATOR", ""))
  end

  def is_omni_eth_bridge?(nil), do: false

  def is_omni_eth_bridge?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)

    address_hash_str == String.downcase(System.get_env("ETH_OMNI_BRIDGE_MEDIATOR", "")) ||
      address_hash_str == String.downcase(System.get_env("ETH_OMNI_BRIDGE", ""))
  end

  def is_omni_bsc_bridge?(nil), do: false

  def is_omni_bsc_bridge?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)

    address_hash_str == String.downcase(System.get_env("BSC_OMNI_BRIDGE_MEDIATOR", "")) ||
      address_hash_str == String.downcase(System.get_env("BSC_OMNI_BRIDGE", ""))
  end

  def is_xmoon_token?(nil), do: false

  def is_xmoon_token?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)

    address_hash_str == String.downcase(System.get_env("RINKEBY_XMOON_TOKEN", ""))
  end

  def is_xbrick_token?(nil), do: false

  def is_xbrick_token?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)

    address_hash_str == String.downcase(System.get_env("RINKEBY_XBRICK_TOKEN", ""))
  end

  def is_amb_bridge?(nil), do: false

  def is_amb_bridge?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("AMB_BRIDGE_ADDRESSES", "")) =~ address_hash_str
  end

  def is_amb_bridge_mediators?(nil), do: false

  def is_amb_bridge_mediators?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)

    String.downcase(System.get_env("AMB_BRIDGE_MEDIATORS", "")) =~ address_hash_str ||
      String.downcase(System.get_env("CUSTOM_AMB_BRIDGE_MEDIATORS", "")) =~ address_hash_str
  end

  def is_perp_fi?(nil), do: false

  def is_perp_fi?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_PERP_FI", "")) =~ address_hash_str
  end

  def is_df_0_5?(nil), do: false

  def is_df_0_5?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_DARK_FOREST_V_0_5", "")) =~ address_hash_str
  end

  def is_df_0_6?(nil), do: false

  def is_df_0_6?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_DARK_FOREST_V_0_6", "")) =~ address_hash_str
  end

  def is_df_0_6_r2?(nil), do: false

  def is_df_0_6_r2?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_DARK_FOREST_V_0_6_r2", "")) =~ address_hash_str
  end

  def is_df_0_6_r3?(nil), do: false

  def is_df_0_6_r3?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_DARK_FOREST_V_0_6_r3", "")) =~ address_hash_str
  end

  def is_hopr?(nil), do: false

  def is_hopr?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_HOPR", "")) =~ address_hash_str
  end

  def is_test?(nil), do: false

  def is_test?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_TEST_TOKEN", "")) =~ address_hash_str
  end

  def is_gtgs?(nil), do: false

  def is_gtgs?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_GTGS_TOKEN", "")) =~ address_hash_str
  end

  def is_spam?(nil), do: false

  def is_spam?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_SPAM", "")) =~ address_hash_str
  end

  def is_lewinswap?(nil), do: false

  def is_lewinswap?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_LEWINSWAP", "")) =~ address_hash_str
  end

  def is_lewinswap_farm?(nil), do: false

  def is_lewinswap_farm?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_LEWINSWAP_FARM", "")) =~ address_hash_str
  end

  def is_lewinswap_stake?(nil), do: false

  def is_lewinswap_stake?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_LEWINSWAP_STAKE", "")) =~ address_hash_str
  end

  def is_swarm?(nil), do: false

  def is_swarm?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_SWARM", "")) =~ address_hash_str
  end

  def is_cryptostamps?(nil), do: false

  def is_cryptostamps?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_CRYPTOSTAMPS", "")) =~ address_hash_str
  end

  def is_curve?(nil), do: false

  def is_curve?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_CURVE", "")) =~ address_hash_str
  end

  def is_useless_mev_machine?(nil), do: false

  def is_useless_mev_machine?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_USELESS_MEV_MACHINE", "")) =~ address_hash_str
  end

  def is_tornado_cash?(nil), do: false

  def is_tornado_cash?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_TORNADO_CASH", "")) =~ address_hash_str
  end

  def is_sana?(nil), do: false

  def is_sana?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_SANA", "")) =~ address_hash_str
  end

  def is_chainlink_oracle?(nil), do: false

  def is_chainlink_oracle?(address_hash) do
    address_hash_str = "0x" <> Base.encode16(address_hash.bytes, case: :lower)
    String.downcase(System.get_env("CUSTOM_CONTRACT_ADDRESSES_CHAINLINK_ORACLES", "")) =~ address_hash_str
  end

  def get_chainlink_oracle_name(oracle_address) do
    if oracle_address do
      chainlink_oracles_config = Application.get_env(:block_scout_web, :chainlink_oracles)

      if chainlink_oracles_config do
        try do
          chainlink_oracle =
            chainlink_oracles_config
            |> Parser.parse!(%{keys: :atoms!})
            |> Enum.find(fn %{:name => _name, :address => address} ->
              String.downcase(address) == String.downcase(oracle_address)
            end)

          chainlink_oracle[:name]
        rescue
          _ ->
            ""
        end
      else
        ""
      end
    else
      ""
    end
  end
end
