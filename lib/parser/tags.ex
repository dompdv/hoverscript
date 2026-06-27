defmodule Hoverscript.Parser.Tags do
  @parameters_table %{
    heading: %{
      authorized_parameters: ["level"],
      default_parameters: %{level: 1},
      check_parameters: &Hoverscript.Parser.Tags.check_heading_parameters/2
    },
    list: %{
      authorized_parameters: ["level"],
      default_parameters: %{level: 1, counter: "1"},
      check_parameters: &Hoverscript.Parser.Tags.check_list_parameters/2
    },
    num: %{
      authorized_parameters: ["level", "counter"],
      default_parameters: %{level: 1, counter: "1"},
      check_parameters: &Hoverscript.Parser.Tags.check_num_parameters/2
    },
    checklist: %{
      authorized_parameters: ["checked"],
      default_parameters: %{checked: false},
      check_parameters: &Hoverscript.Parser.Tags.check_checklist_parameters/2
    },
    quote: %{
      authorized_parameters: ["name"],
      default_parameters: %{name: :default_quote},
      check_parameters: &Hoverscript.Parser.Tags.check_quote_parameters/2
    },
    para: %{
      authorized_parameters: ["align", "frame"],
      default_parameters: %{align: "justify"},
      check_parameters: &Hoverscript.Parser.Tags.check_para_parameters/2
    },
    sep: %{
      authorized_parameters: ["type"],
      default_parameters: %{type: "line"},
      check_parameters: &Hoverscript.Parser.Tags.check_sep_parameters/2
    },
    footnote: %{
      authorized_parameters: ["ref"],
      default_parameters: %{ref: nil},
      check_parameters: &Hoverscript.Parser.Tags.check_footnote_parameters/2
    },
    title: %{
      authorized_parameters: ["align"],
      default_parameters: %{align: "center"},
      check_parameters: &Hoverscript.Parser.Tags.check_title_parameters/2
    },
    slot: %{
      authorized_parameters: ["name"],
      default_parameters: %{name: nil},
      check_parameters: &Hoverscript.Parser.Tags.check_slot_parameters/2
    },
    verbatim: %{
      authorized_parameters: ["name", "type", "lang"],
      default_parameters: %{name: :default_verbatim},
      check_parameters: &Hoverscript.Parser.Tags.check_verbatim_parameters/2
    },
    # Inline options
    i_footnote: %{
      authorized_parameters: ["ref"],
      default_parameters: %{ref: :default_ref},
      check_parameters: &Hoverscript.Parser.Tags.check_i_footnote_parameters/2
    },
    i_image: %{
      authorized_parameters: ["name"],
      default_parameters: %{name: :image_name},
      check_parameters: &Hoverscript.Parser.Tags.check_i_image_parameters/2
    },
    i_link: %{
      authorized_parameters: ["url"],
      default_parameters: %{url: :default_link},
      check_parameters: &Hoverscript.Parser.Tags.check_i_link_parameters/2
    }
  }

  # Inline options have some default parameters which are unnamed
  # Construct default parameters and call parse_options
  @spec parse_inline_options(any, any, any) ::
          {:error, {:unauthorized_parameters, list} | {:parameter_errors, any, any}}
          | {:ok, any}
          | {:ok, any, any}
  def parse_inline_options(tag, [], raw_options), do: parse_options(tag, [], raw_options)

  def parse_inline_options(:num, [{:no_value, str_level}, {"counter", counter}], raw_options),
    do: parse_options(:num, [{"level", str_level}, {"counter", counter}], raw_options)

  def parse_inline_options(tag, [{:no_value, str_level} | other_parameters], raw_options)
      when tag == :heading or tag == :list or tag == :num,
      do: parse_options(tag, [{"level", str_level} | other_parameters], raw_options)

  def parse_inline_options(tag, [{:no_value, str_level} | other_parameters], raw_options)
      when tag == :checklist,
      do: parse_options(tag, [{"checked", str_level} | other_parameters], raw_options)

  def parse_inline_options(:para, [{:no_value, str_level} | other_parameters], raw_options),
    do: parse_options(:para, [{"align", str_level} | other_parameters], raw_options)

  def parse_inline_options(:title, [{:no_value, str_level} | other_parameters], raw_options),
    do: parse_options(:title, [{"align", str_level} | other_parameters], raw_options)

  def parse_inline_options(:slot, [{:no_value, name} | other_parameters], raw_options),
    do: parse_options(:slot, [{"name", name} | other_parameters], raw_options)

  def parse_inline_options(:sep, [{:no_value, type} | other_parameters], raw_options),
    do: parse_options(:sep, [{"type", type} | other_parameters], raw_options)

  def parse_inline_options(:quote, [{:no_value, name} | other_parameters], raw_options),
    do: parse_options(:quote, [{"name", name} | other_parameters], raw_options)

  def parse_inline_options(:footnote, [{:no_value, ref} | other_parameters], raw_options),
    do: parse_options(:footnote, [{"ref", ref} | other_parameters], raw_options)

  def parse_inline_options(:verbatim, [{:no_value, name} | other_parameters], raw_options),
    do: parse_options(:verbatim, [{"name", name} | other_parameters], raw_options)

  # Inline options
  def parse_inline_options(:i_footnote, [{:no_value, ref} | other_parameters], raw_options),
    do: parse_options(:i_footnote, [{"ref", ref} | other_parameters], raw_options)

  def parse_inline_options(tag, parameters, raw_options),
    do: parse_options(tag, parameters, raw_options)

  ### Utility functions ###

  def unautorized_parameters(tag, parameters) do
    for {param, value} <- parameters,
        param not in @parameters_table[tag][:authorized_parameters] do
      if param == :no_value, do: value, else: param
    end
  end

  ##### Common to HEADING, LIST, NUM tags #####

  # Parse options for all tags
  def parse_options(tag, [], _) do
    {:ok, @parameters_table[tag][:default_parameters]}
  end

  def parse_options(tag, parameters, raw_options) do
    # Check if there are unauthorized parameters
    unauthorized = unautorized_parameters(tag, parameters)
    # TODO: check authorized parameters
    atom_parameters =
      for {param, value} <- parameters,
          param != :no_value,
          param not in unauthorized,
          do: {String.to_atom(param), value}

    # Check parameters
    case Enum.reduce(atom_parameters, {%{}, []}, @parameters_table[tag][:check_parameters])
         |> then(fn
           {options, []} -> {:ok, options}
           {_options, errors} -> {:error, {:parameter_errors, errors, raw_options}}
         end) do
      {:ok, options} ->
        if unauthorized == [],
          do: {:ok, options},
          else: {:error, [{:unauthorized_parameters, unauthorized}]}

      {:error, error} ->
        if unauthorized == [],
          do: {:error, [error]},
          else: {:error, [error, {:unauthorized_parameters, unauthorized}]}
    end
  end

  ## Utility functions for parameters checking ##

  def check_integer_parameter({param, value}, {options, errors}) do
    case Integer.parse(value) do
      :error -> {options, [{:invalid_integer, param, value} | errors]}
      {l, _} -> {Map.put(options, param, l), errors}
    end
  end

  def check_positive_integer_parameter({param, value}, {options, errors}) do
    case Integer.parse(value) do
      :error -> {options, [{:invalid_integer, param, value} | errors]}
      {l, _} when l >= 0 -> {Map.put(options, param, l), errors}
      _ -> {options, [{:invalid_integer, param, value} | errors]}
    end
  end

  def check_integer_range_parameter({param, value}, {options, errors}, range) do
    case Integer.parse(value) do
      :error -> {options, [{:invalid_integer, param, value} | errors]}
      {l, _} when l >= range.first and l <= range.last -> {Map.put(options, param, l), errors}
      _ -> {options, [{:out_of_range_integer, param, value} | errors]}
    end
  end

  ##### HEADING TAG #####
  def check_heading_parameters({:level, _str_level} = param, acc),
    do: check_integer_range_parameter(param, acc, 1..6)

  ##### LIST TAG #####
  def check_list_parameters({:level, _str_level} = param, acc),
    do: check_integer_range_parameter(param, acc, 1..3)

  ##### NUM TAG #####
  def check_num_parameters({:level, _str_level} = param, acc),
    do: check_integer_range_parameter(param, acc, 1..3)

  def check_num_parameters({:counter, _str_level} = param, acc),
    do: check_positive_integer_parameter(param, acc)

  ##### PARA TAG #####
  def check_para_parameters({:align, value} = param, {options, errors}) do
    if value in ["center", "right", "left", "justify"],
      do: {Map.put(options, :align, value), errors},
      else: {options, [{:invalid_alignment, param, value} | errors]}
  end

  def check_para_parameters({:frame, _value} = param, acc),
    do: check_positive_integer_parameter(param, acc)

  #### QUOTE TAG #####
  def check_quote_parameters({:name, value} = param, {options, errors}) do
    value = if is_binary(value), do: String.trim(value), else: value

    if value != "",
      do: {Map.put(options, :name, value), errors},
      else: {options, [{:invalid_name, param, value} | errors]}
  end

  ##### FOOTNOTE TAG #####
  def check_footnote_parameters({:ref, value} = param, {options, errors}) do
    if value != nil and value != "",
      do: {Map.put(options, :ref, value), errors},
      else: {options, [{:unspecified_reference, param, value} | errors]}
  end

  ##### TITLE TAG #####
  def check_title_parameters({:align, value} = param, {options, errors}) do
    if value in ["center", "right", "left", "justify"],
      do: {Map.put(options, :align, value), errors},
      else: {options, [{:invalid_alignment, param, value} | errors]}
  end

  ##### SLOT TAG #####
  def check_slot_parameters({:name, value} = param, {options, errors}) do
    if value != nil and value != "",
      do: {Map.put(options, :name, value), errors},
      else: {options, [{:invalid_alignment, param, value} | errors]}
  end

  ##### SEP TAG #####
  def check_sep_parameters({:type, value} = param, {options, errors}) do
    value = String.downcase(value)

    if value in ["line", "stars", "asterism", "dinkus"],
      do: {Map.put(options, :type, value), errors},
      else: {options, [{:invalid_type, param, value} | errors]}
  end

  ##### CHECKLIST TAG #####
  def check_checklist_parameters({:checked, checked}, {options, errors}) do
    cond do
      checked == "X" or checked == "x" -> {Map.put(options, :checked, true), errors}
      true -> {options, [{:invalid_checked_symbol, :checked, checked} | errors]}
    end
  end

  ##### VERBATIM TAG #####
  def check_verbatim_parameters({:name, value}, {options, errors}) do
    {Map.put(options, :name, value), errors}
  end

  def check_verbatim_parameters({:lang, value} = param, {options, errors}) do
    value = String.downcase(value)

    if value in ["html", "js", "elixir"],
      do: {Map.put(options, :lang, value), errors},
      else: {options, [{:invalid_language, param, value} | errors]}
  end

  def check_verbatim_parameters({:type, value} = param, {options, errors}) do
    value = String.downcase(value)

    if value in ["code"],
      do: {Map.put(options, :type, value), errors},
      else: {options, [{:invalid_type, param, value} | errors]}
  end

  ##### INLINE OPTIONS #####
  #### I_FOOTNOTE TAG #####
  def check_i_footnote_parameters({:ref, value} = param, {options, errors}) do
    if value != nil and value != "",
      do: {Map.put(options, :ref, value), errors},
      else: {options, [{:unspecified_reference, param, value} | errors]}
  end

  #### I_IMAGE TAG #####
  def check_i_image_parameters({:name, value} = param, {options, errors}) do
    if value != nil and value != "",
      do: {Map.put(options, :name, value), errors},
      else: {options, [{:unspecified_image_name, param, value} | errors]}
  end
  #### I_LINK TAG #####
  def check_i_link_parameters({:url, value} = param, {options, errors}) do
    if value != nil and value != "",
      do: {Map.put(options, :url, value), errors},
      else: {options, [{:unspecified_url, param, value} | errors]}
  end

end
