defmodule Hoverscript.Parser.Tagline do
  # Parse a tagline. Relies on the Tags module to validate the parameters and the Options module to parse the options
  alias Hoverscript.Parser.Tags
  alias Hoverscript.Parser.Options

  @long_tag_regex ~r/^:([a-zA-Z_]+):([^\/]*)\/(.*)$/u
  @short_tag_regex ~r/^:([a-zA-Z_]+)[\s\t](.*)$/u
  @lonely_short_tag_regex ~r/^:([a-zA-Z_]+):?\/?$/u

  @tags %{
    "heading" => :heading,
    "h" => :heading,
    "num" => :num,
    "n" => :num,
    "list" => :list,
    "l" => :list,
    "q" => :quote,
    "quote" => :quote,
    "block" => :block,
    "p" => :para,
    "para" => :para,
    "separator" => :sep,
    "sep" => :sep,
    "footnote" => :footnote,
    "slot" => :slot,
    "title" => :title,
    "verbatim" => :verbatim,
    "cl" => :checklist,
    "checklist" => :checklist
  }
  @available_tags Map.keys(@tags)
  @tags_with_no_body [:sep, :quote, :footnote, :slot, :verbatim]

  @inline_tag_regex ~r/^:([a-zA-Z_]+):(.*)$/u
  @inline_tags %{
    "image" => :i_image,
    "img" => :i_image,
    "footnote" => :i_footnote,
    "link" => :i_link
  }

  @available_inline_tags Map.keys(@inline_tags)

  def build_shortcut_answer(tag, tag_name, body) do
    %{
      tag: tag,
      options: %{level: String.length(tag_name) - 1},
      tag_name: tag_name,
      body: body,
      tag_expr: tag_name
    }
  end

  # parse a tag line. A tag line has the form either ":tag" or ":tag: option1, option2/"
  # The validation of the valid options per tag is done in Hoverscript.Tags
  def parse_tag_line(str) do
    trimmed = String.trim_leading(str)

    [extract_tag, rest] =
      case String.split(trimmed, [" ", "\t"], parts: 2) do
        [tag] -> [tag, ""]
        l -> l
      end

    cond do
      extract_tag in [":=", ":==", ":===", ":====", ":=====", ":======", ":======="] ->
        build_shortcut_answer(:heading, extract_tag, rest)

      extract_tag in [":.", ":..", ":...", ":....", ":.....", ":......", ":......."] ->
        build_shortcut_answer(:num, extract_tag, rest)

      extract_tag in [":*", ":**", ":***", ":****", ":*****", ":******", ":*******"] ->
        build_shortcut_answer(:list, extract_tag, rest)

      # A tag line with a long tag (:tag:options/body)) the body can be empty
      Regex.match?(@long_tag_regex, trimmed) ->
        parse_long_tag(trimmed)

      # A tag line with a short tag (:tag body)
      Regex.match?(@short_tag_regex, trimmed) ->
        parse_short_tag(trimmed)

      # A tag line with a lonely short tag (:tag or :tag/). Nothing else on the line
      Regex.match?(@lonely_short_tag_regex, trimmed) ->
        parse_lonely_short_tag(trimmed)

      true ->
        case String.split(trimmed, " ", parts: 2) do
          [tag, rest] -> {:error, %{error: :unknown_tag, tag_name: tag, body: rest}}
          _ -> {:error, %{error: :unknown_tag, tag_name: trimmed, body: ""}}
        end
    end
  end

  # A tag line with a long tag (:tag:options/body)) the body can be empty
  def parse_long_tag(str) do
    [_, tag, options, rest] =
      Regex.run(@long_tag_regex, str)

    tag_expr = ":#{tag}:#{String.trim(options)}/"

    cond do
      tag in @available_tags ->
        tag_atom = @tags[tag]

        parsed_options =
          if(String.trim(options) == "", do: [], else: Options.parse_options_inline(options))

        tag_parsed_options =
          Tags.parse_inline_options(tag_atom, parsed_options, options)

        case tag_parsed_options do
          {:error, error} ->
            {:error, {error, %{tag_name: tag, body: rest, tag_expr: tag_expr}}}

          {:ok, tag_options} ->
            if tag_atom in @tags_with_no_body and String.trim(rest) != "" do
              {:error, {:tagline_not_empty, %{tag_name: tag, body: rest, tag_expr: tag_expr}}}
            else
              %{
                tag: tag_atom,
                options: tag_options,
                tag_name: tag,
                body: rest,
                tag_expr: tag_expr
              }
            end
        end

      true ->
        {:error, {:unknown_tag, %{tag_name: tag, body: rest}}}
    end
  end

  # A tag line with a short tag (:tag body)
  def parse_short_tag(str) do
    [_, tag, rest] = Regex.run(@short_tag_regex, str)

    cond do
      # Put a warning to warn about possible forgotten colon after tag. (like :tag option/body instead of :tag:option/body)
      String.contains?(str, "/") and tag in @available_tags ->
        {:warning,
         %{
           error: {:maybe_forgot_colon_after_tag, tag},
           tag: @tags[tag],
           options: Tags.parse_inline_options(@tags[tag], [], ""),
           tag_name: tag,
           tag_expr: ":#{tag}",
           body: rest
         }}

      tag in @available_tags ->
        tag_atom = @tags[tag]

        if tag_atom in @tags_with_no_body and String.trim(rest) != "" do
          {:error, {:tagline_not_empty, %{tag_name: tag, body: rest}}}
        else
          %{
            tag: @tags[tag],
            # elem(1) because the function returns {:ok, options}
            options: Tags.parse_inline_options(@tags[tag], [], "") |> elem(1),
            tag_name: tag,
            tag_expr: ":#{tag}",
            body: rest
          }
        end

      true ->
        {:error, {:unknown_tag, %{tag_name: tag, body: rest}}}
    end
  end

  # A tag line with a lonely short tag (:tag or :tag/). Nothing else on the line
  def parse_lonely_short_tag(str) do
    [_, tag] = Regex.run(@lonely_short_tag_regex, str)

    if tag in @available_tags do
      %{
        tag: @tags[tag],
        # elem(1) because the function returns {:ok, options}
        options: Tags.parse_inline_options(@tags[tag], [], "") |> elem(1),
        tag_name: tag,
        tag_expr: ":#{tag}",
        body: ""
      }
    else
      {:error, %{error: {:unknown_tag, tag}, tag_name: tag, body: ""}}
    end
  end

  # Parse tags when they are in an inline context like
  # [:tag: par1=val1]++ text ++
  def parse_inline_tag(str) do
    [_, tag, options] =
      Regex.run(@inline_tag_regex, str)

    cond do
      tag in @available_inline_tags ->
        tag_atom = @inline_tags[tag]

        parsed_options =
          if(String.trim(options) == "", do: [], else: Options.parse_options_inline(options))

        tag_parsed_options =
          Tags.parse_inline_options(tag_atom, parsed_options, options)

        case tag_parsed_options do
          {:error, error} ->
            {:error, %{error: error, tag_name: tag, options: options}}

          {:ok, tag_options} ->
            %{
              tag: tag_atom,
              options: tag_options,
              tag_name: tag
            }
        end

      true ->
        {:error, %{error: {:unknown_tag, tag}, tag_name: tag, options: options}}
    end
  end
end
