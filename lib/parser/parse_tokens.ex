defmodule Hoverscript.Parser.ParseTokens do
  @list_item_types [:num, :list]
  @list_types_map %{num: :ordered_list, list: :bullet_list}
  @list_types [:ordered_list, :bullet_list]

  @moduledoc """
  This is the core parser. It takes a token list and produces a tree representing the document.
  In this case, each line of the file is a token.
  Nota: the parsing of the content itself (** for bold for example) is done in another pass.

  How does it work ?
   - The core idea is that the token list will be progressively consumed, token after token, in a top-level loop. This loop is implemented by
     pinc(tokens, state, stage, stack).
      * Tokens are the lines to parse, state is the current state of the parser, stage is the stage within the current state, stack is the stack of the current context.
      * Stack: The stack (the context) is necessary because the nodes are naturally nested. For example, the root node is called :document and contains a list of :blocks.
        Each element of the stack contains the a node of the syntax tree to be built. The top element of the stack is the node currently built.
      * State :The state is the type of the node currently built (so it's the same as the :type of the node on the top of the stack)
      * Stage: A node needs sometimes several subnodes. For example, a bullet list item has a text content and potentially some nested lists. The stage will represent this
        "sub state". For example :nested. Note that the nodes in the stack have a :stage entry to follow this
    - The loop will call the central function that consumes the current token. This function is implemented by run(tokens, state, stage, stack)
      This function will behave very differently according to the stage, the stage and the first token of the line. This is where the grammar is implemented
      The function return instructs the main loop about what to do:
      * `{:run, shift, acc}` : move the cursor by shift tokens, replace the top level node by acc. When the current node process tokens and accumulate them
      * `{:ignore, shift}` -> move the cursor by shift tokens,
      * `{:start, shift, new_state, new_stage, line}` : move the cursor by shift tokens, create a new node, push it to the stack and switch to a new state and stage. When the node
        needs to parse a subnode. Each node has to implement a start(state, line) function that returns a new node. The line is the first line of the new node.
      * `{:end, shift, accumulator}` : move the cursor by shift tokens, remove the current node from the top of the stack , update the parent node with the current node (in accumulator)
        move to the previous state and stage. This is when a node is completed. Each non terminal node has to implement a update(state, stage, stack, child_node) function
        to indicate how and where to store the child_node and the structure. The parent node is at the top of the stack, so update modifies the stack
      * `{:end_stage, shift, next_stage, accumulator}` : move the cursor by shift tokens, switch to the next stage, update the top of the stack with the updated node (accumulator)
        When a node has completed a stage
    - the parsing starts by putting the root node (:document) on the stack and launching pinc.
    - a node is a map in the form of
      ```
      %{
        type:           :para, :heading, etc
        stage:          :lines, :blocks, etc
        line_number:    line_number of the start of the node
        raw_lines: [],  optional: list of line tokens
        options: %{}    optional: associated tag options
        body:           optional: the text of the node
        joined_lines:   optional: the text of the node (if there are several lines)
        level:          optional: level of the :heading, :num, :list, :ordered_list, :bullet_list
        blocks:         optional list of terminal blocks
        items:          optional: list of items for ordrered and bullet list
        children:       optional: list of blocks for :document
        nested:         optional: list of nested structure for ordered and bullet lists
      }
      ```
  An example:
   The :document state has one stage called :children:. (when there is one stage, the name is not significant).
   The run(tokens, :document,_, stack) function will return:
   * `{:ignore,1}` if the first token is a blankline
   * `{:start, :heading,...}` if the first token is a :heading to launch the parsing of a :heading node
   When the parsing of the :heading node is over (returning {:end,...}), the update(:document, _, [doc|r], heading_node) function is called.
   The function will append to the :children: entry of the :document node map the heading_node


   Parser structure and nodes :
    ```
    :document -> children: [:para | :heading | :ordered_list | :bullet_list | :literal]
    :literal -> raw_lines: [:blankline | :optionline | :continueline]
    :sep ->
    :para -> raw_lines: [line tokens]
    :title -> raw_lines: [line tokens]
    :heading -> raw_lines: [line tokens] nested: [blocks]
    :quote -> nested: [blocks]
    :footnote -> nested: [blocks]
    :slot -> nested: [blocks]
    :ordered_list -> items: [:num]
    :bullet_list -> items: [:list]
    :num -> raw_lines: [line tokens] + blocks: :continued_list_of_blocks + nested: [:ordered_list | :bullet_list]
    :continued_list_of_blocks -> blocks: [:para | :literal]
    ```
  """

  @doc """
  Parse line tokens and create an tree representation of the document
  """
  def parse(lines) do
    # Launch parsing with the document node
    case pinc(lines, :document, :children, [start(:document, nil)], []) do
      {doc, []} -> {:ok, doc}
      {doc, errors} -> {:error, :parsing_error, errors, doc}
    end
  end

  ######### pinc parses incrementally a list of lines (each line is a token)

  # No more tokens, and only one state in the stack: we are done
  def pinc([], _state, _stage, [top], errors), do: {top, Enum.reverse(errors)}

  # No more tokens, but there are several states in the stack: we need end properly each state
  def pinc([], state, stage, [_ | rstack] = stack, errors) do
    {ran, new_error} =
      case run(:eof, state, stage, stack) do
        {_, _} = with_error -> with_error
        ran -> {ran, nil}
      end

    new_errors = if new_error != nil, do: [new_error | errors], else: errors

    case ran do
      # update the previous state with the finalized current node
      {:end, _, accumulator} ->
        %{type: previous_state, stage: previous_stage} = hd(rstack)
        new_stack = update(previous_state, previous_stage, rstack, accumulator)
        # continue to unstack
        pinc([], previous_state, previous_stage, new_stack, new_errors)

      {:end_stage, _, next_stage, accumulator} ->
        # continue the stages
        pinc(
          [],
          state,
          next_stage,
          [Map.put(accumulator, :stage, next_stage) | rstack],
          new_errors
        )
    end
  end

  # The standard case: we have a token to parse
  def pinc(lines, state, stage, [_ | rstack] = stack, errors) do
    # Process one token
    {ran, new_error} =
      case run(lines, state, stage, stack) do
        {_, _} = with_error -> with_error
        ran -> {ran, nil}
      end

    new_errors = if new_error != nil, do: [new_error | errors], else: errors

    case ran do
      # The token indicates that it is accumulating
      {:run, shift, acc} ->
        pinc(lshift(lines, shift), state, stage, [acc | rstack], new_errors)

      # The token indicates that we need to ignore it and move to the next token
      #      {:ignore, shift} ->
      #        pinc(lshift(lines, shift), state, stage, stack, new_errors)

      # The token indicates that we need to start a new state that we put on the stack
      # shift is the number of lines to skip. Indeed, we sometimes need to stay on the same token and sometime it is processed by the starting state
      {:start, shift, new_state, new_stage, line} ->
        pinc(
          lshift(lines, shift),
          new_state,
          new_stage,
          [start(new_state, line) | stack],
          new_errors
        )

      # The token indicates that we need to end the current state. Some post processing is done and put in accumulator
      {:end, shift, accumulator} ->
        %{type: previous_state, stage: previous_stage} = hd(rstack)
        # updating the previous node with the finalized current node
        new_stack = update(previous_state, previous_stage, rstack, accumulator)
        # return to the previous state
        pinc(lshift(lines, shift), previous_state, previous_stage, new_stack, new_errors)

      {:end_stage, shift, next_stage, accumulator} ->
        pinc(
          lshift(lines, shift),
          state,
          next_stage,
          [Map.put(accumulator, :stage, next_stage) | rstack],
          new_errors
        )
    end
  end

  #### Document
  def start(:document, _), do: %{type: :document, stage: :children, line_number: 0, children: []}

  #### Literal
  def start(:literal, {_, line_number, _} = line) do
    %{
      type: :literal,
      stage: :line,
      line_number: line_number,
      raw_lines: [line]
    }
  end

  ### Para (without tag)
  def start(:para, {:line, line_number, _}),
    do: %{
      type: :para,
      stage: :lines,
      line_number: line_number,
      raw_lines: [],
      options: %{},
      optionline: nil,
      tag_expr: ""
    }

  ### Para (with tag)
  def start(:para, {:para, line_number, desc}) do
    %{raw_line: raw_line} = desc

    Map.merge(
      desc,
      %{
        type: :para,
        stage: :lines,
        line_number: line_number,
        raw_lines: [{:line, line_number, raw_line}]
      }
    )
  end

  ### Title
  def start(:title, {:title, line_number, desc}) do
    %{raw_line: raw_line} = desc

    Map.merge(
      desc,
      %{
        type: :title,
        stage: :lines,
        line_number: line_number,
        raw_lines: [{:line, line_number, raw_line}]
      }
    )
  end

  ### Quote
  def start(:quote, {:quote, line_number, desc}) do
    %{raw_line: raw_line} = desc

    Map.merge(
      desc,
      %{
        type: :quote,
        stage: :nested,
        line_number: line_number,
        raw_lines: [{:line, line_number, raw_line}],
        nested: []
      }
    )
  end

  ### Sep
  def start(:sep, {:sep, line_number, desc}) do
    %{body: body} = desc

    Map.merge(
      desc,
      %{
        type: :sep,
        stage: :none,
        line_number: line_number,
        raw_lines: [{:sep, line_number, body}]
      }
    )
  end

  ### Heading, Num & List
  def start(tag, {tag, line_number, desc})
      when tag in [:heading, :num, :list] do
    %{options: %{level: l}, raw_line: raw_line} = desc

    Map.merge(
      desc,
      %{
        type: tag,
        stage: :lines,
        line_number: line_number,
        raw_lines: [{:line, line_number, raw_line}],
        level: l,
        blocks: [],
        nested: []
      }
    )
  end

  ### Ordered_list and bullet_list
  def start(tag, {_, line_number, %{options: %{level: l}}})
      when tag in @list_types do
    %{
      type: tag,
      stage: :items,
      line_number: line_number,
      level: l,
      items: []
    }
  end

  ### Continued_list_of_blocks
  def start(:continued_list_of_blocks, {:continueline, line_number, _}),
    do: %{
      type: :continued_list_of_blocks,
      stage: :blocks,
      line_number: line_number,
      blocks: []
    }

  ### Footnote
  def start(tag, {tag, line_number, desc}) when tag in [:footnote, :slot] do
    %{raw_line: raw_line} = desc

    Map.merge(
      desc,
      %{
        type: tag,
        stage: :nested,
        line_number: line_number,
        raw_lines: [{:line, line_number, raw_line}],
        nested: []
      }
    )
  end

  def start(:verbatim, {:verbatim, line_number, desc}) do
    Map.merge(
      desc,
      %{
        type: :verbatim,
        stage: :lines,
        line_number: line_number,
        raw_lines: []
      }
    )
  end

  ###### UPDATES : called when a node is finished and popped from the stack. The calling node can be updated with the completed child node.

  ### Document
  # document is a list of blocks
  def update(:document, _, [acc | r], fstack) do
    [%{acc | children: acc[:children] ++ [fstack]} | r]
  end

  ### Nested stage for :
  ### quote
  ### footnote
  ### heading
  def update(tag, :nested, [acc | r], fstack) when tag in [:quote, :footnote, :heading, :slot] do
    [%{acc | nested: acc[:nested] ++ [fstack]} | r]
  end

  ### ordered_list
  # ...is a list of items
  def update(tag, _, [acc | r], fstack) when tag in @list_types do
    [%{acc | items: acc[:items] ++ [fstack]} | r]
  end

  ### continued_list_of_blocks
  # ...is a list of blocks
  def update(:continued_list_of_blocks, :blocks, [acc | r], fstack) do
    [%{acc | blocks: acc[:blocks] ++ [fstack]} | r]
  end

  ### num  & list
  # Stage blocks
  # called when the gathering of the continued list of blocks is over
  def update(tag, :blocks, [acc | r], %{type: :continued_list_of_blocks} = fstack)
      when tag in @list_item_types do
    [%{acc | blocks: fstack[:blocks]} | r]
  end

  # Stage nested
  def update(tag, :nested, [acc | r], %{type: context} = fstack)
      when tag in @list_item_types and context in @list_types do
    [%{acc | nested: acc[:nested] ++ [fstack]} | r]
  end

  # verbatim
  def update(:verbatim, _, [acc | r], fstack) do
    [%{acc | raw_lines: acc[:raw_lines] ++ [fstack]} | r]
  end

  ####### Document - Top level blocks
  # Ignore blanklines or continuelines
  #  def run([{:blankline, _, _} | _], :document, _, _), do: {:ignore, 1}
  def run([{tag, _, _} = line | _], :document, _, _)
      when tag in [:blankline, :continueline, :optionline],
      do: {:start, 1, :literal, :line, line}

  # A :line token indicates the start of a :para
  def run([{:line, _, _} = line | _], :document, _, _), do: {:start, 0, :para, :lines, line}
  # A :para token is also a :para, but with a tag
  def run([{:para, _, _} = line | _], :document, _, _), do: {:start, 1, :para, :lines, line}

  # :title
  def run([{:title, _, _} = line | _], :document, _, _), do: {:start, 1, :title, :lines, line}

  # Quote, footnote, slot
  def run([{tag, _, _} = line | _], :document, _, _) when tag in [:quote, :footnote, :slot],
    do: {:start, 1, tag, :nested, line}

  # A verbatim token
  def run([{:verbatim, _, _} = line | _], :document, _, _),
    do: {:start, 1, :verbatim, :lines, line}

  # A :sep token
  def run([{:sep, _, _} = line | _], :document, _, _), do: {:start, 1, :sep, :none, line}

  # A :heading token is the start of a :heading
  def run([{:heading, _, _} = line | _], :document, _, _), do: {:start, 1, :heading, :lines, line}

  # A :num token is the start of a :ordered_list
  def run([{:num, _, _} = line | _], :document, _, _),
    do: {:start, 0, :ordered_list, :items, line}

  # A :list token is the start of a :bullet_list
  def run([{:list, _, _} = line | _], :document, _, _),
    do: {:start, 0, :bullet_list, :items, line}

  def run(:eof, :document, _, [acc | _]),
    do: {:end, 0, acc}

  ######## Literal
  def run(_, :literal, :line, [acc | _]), do: {:end, 0, acc}

  ######## Para
  # if token == :line, accumulate lines
  def run([{:line, _, _} = line | _], :para, :lines, [%{raw_lines: lines} = para | _]) do
    {:run, 1, %{para | raw_lines: lines ++ [line]}}
  end

  # for all other tokens, end the stage
  def run(_, :para, :lines, [acc | _]) do
    # Post processing: join lines and add it to the accumulator
    {:end, 0, Map.put(acc, :joined_lines, join_lines_with_body(acc[:raw_lines], acc[:body]))}
  end

  ######## Title
  # if token == :line, accumulate lines
  def run([{:line, _, _} = line | _], :title, :lines, [%{raw_lines: lines} = node | _]) do
    {:run, 1, %{node | raw_lines: lines ++ [line]}}
  end

  # for all other tokens, end the stage
  def run(_, :title, :lines, [acc | _]) do
    # Post processing: join lines and add it to the accumulator
    {:end, 0, Map.put(acc, :joined_lines, join_lines_with_body(acc[:raw_lines], acc[:body]))}
  end

  ######## Sep
  # End for all tokens
  def run(_, :sep, :none, [acc | _]) do
    {:end, 0, acc}
  end

  ######## Quote, Footnote and Slot at the same time (they are very close)

  # Slot: special case
  # slot can only be nested in document and heading
  def run([{:slot, line_number, _} | _], current_tag, :nested, [acc | _])
      when current_tag not in [:document, :heading, :slot] do
    {{:end, 0, acc},
     {:error, {line_number, 0, line_number, 0}, :slot_only_allowed_document_or_heading}}
  end

  # finishing with error
  def run([{tag, line_number, _} | _], current_tag, :nested, [acc | _])
      when tag in [:heading, :sep, :title] and current_tag in [:footnote, :quote, :slot] do
    {{:end, 0, acc},
     {:error, {line_number, 0, line_number, 0},
      case current_tag do
        :footnote -> :expecting_closing_footnote
        :quote -> :expecting_closing_quote
        :slot -> :expecting_closing_slot
      end}}
  end

  def run(:eof, current_tag, :nested, [acc | _]) when current_tag in [:footnote, :quote, :slot],
    do:
      {{:end, 0, acc},
       {:error, :eof,
        case current_tag do
          :footnote -> :expecting_closing_footnote
          :quote -> :expecting_closing_quote
          :slot -> :expecting_closing_slot
        end}}

  # A quote within a quote
  def run([{:quote, _, desc} = line | _], :quote, :nested, [acc | _]) do
    %{options: %{name: other_name}} = desc
    %{options: %{name: current_name}} = acc
    # if the name of the quote is different, then start a new quote
    # Attention: it is {:end, 1, acc} and not {:end, 0, acc} because we want to skip the line
    if current_name == other_name do
      {:end, 1, Map.put(acc, :closing_tag, desc)}
    else
      {:start, 1, :quote, :nested, line}
    end
  end

  # Footnote in a Quote and Quote in a footnote
  def run([{tag, _, _} = line | _], :quote, :nested, _) when tag in [:footnote],
    do: {:start, 1, tag, :nested, line}

  def run([{tag, _, _} = line | _], :footnote, :nested, _) when tag in [:quote],
    do: {:start, 1, tag, :nested, line}

  def run([{tag, _, _} = line | _], :slot, :nested, _) when tag in [:footnote, :quote],
    do: {:start, 1, tag, :nested, line}

  # Closing footnote tag
  def run([{:footnote, _, desc} | _], :footnote, :nested, [acc | _]),
    do: {:end, 1, Map.put(acc, :closing_tag, desc)}

  # Closing slot tag
  def run([{:slot, _, desc} | _], :slot, :nested, [acc | _]),
    do: {:end, 1, Map.put(acc, :closing_tag, desc)}

  # nesting
  # A :line token indicates the start of a :para
  def run([{:line, _, _} = line | _], current_tag, :nested, _)
      when current_tag in [:footnote, :quote, :slot],
      do: {:start, 0, :para, :lines, line}

  # A :para token is also a :para, but with a tag
  def run([{:para, _, _} = line | _], current_tag, :nested, _)
      when current_tag in [:footnote, :quote, :slot],
      do: {:start, 1, :para, :lines, line}

  def run([{:verbatim, _, _} = line | _], current_tag, :nested, _)
      when current_tag in [:footnote, :quote, :slot],
      do: {:start, 1, :verbatim, :lines, line}

  # A :num token is the start of a :ordered_list
  def run([{:num, _, _} = line | _], current_tag, :nested, _)
      when current_tag in [:footnote, :quote, :slot],
      do: {:start, 0, :ordered_list, :items, line}

  # A :list token is the start of a :bullet_list
  def run([{:list, _, _} = line | _], current_tag, :nested, _)
      when current_tag in [:footnote, :quote, :slot],
      do: {:start, 0, :bullet_list, :items, line}

  def run([{tag, _, _} = line | _], current_tag, :nested, _)
      when tag in [:blankline, :continueline, :optionline] and
             current_tag in [:footnote, :quote, :slot],
      do: {:start, 1, :literal, :line, line}

  ######## Heading
  # if token == :line, accumulate lines
  # Stage: :lines
  def run([{:line, _, _} = line | _], :heading, :lines, [%{raw_lines: lines} = para | _]) do
    {:run, 1, %{para | raw_lines: lines ++ [line]}}
  end

  # for all other tokens, end the stage
  def run(_, :heading, :lines, [acc | _]) do
    # Post processing: join lines and add it to the accumulator
    {:end_stage, 0, :nested,
     Map.put(acc, :joined_lines, join_lines_with_body(acc[:raw_lines], acc[:body]))}
  end

  def run([{tag, _, _} = line | _], :heading, :nested, _)
      when tag in [:blankline, :continueline, :optionline],
      do: {:start, 1, :literal, :line, line}

  # Stage: nested
  # A :line token indicates the start of a :para
  def run([{:line, _, _} = line | _], :heading, :nested, _), do: {:start, 0, :para, :lines, line}
  # A :para token is also a :para, but with a tag
  def run([{:para, _, _} = line | _], :heading, :nested, _), do: {:start, 1, :para, :lines, line}

  # :title
  def run([{:title, _, _} = line | _], :heading, :nested, _),
    do: {:start, 1, :title, :lines, line}

  # :verbatim
  def run([{:verbatim, _, _} = line | _], :heading, :nested, _),
    do: {:start, 1, :verbatim, :lines, line}

  # quote
  def run([{tag, _, _} = line | _], :heading, :nested, _) when tag in [:footnote, :quote, :slot],
    do: {:start, 1, tag, :nested, line}

  # A :sep token
  def run([{:sep, _, _} = line | _], :heading, :nested, _), do: {:start, 1, :sep, :none, line}

  # A :num token is the start of a :ordered_list
  def run([{:num, _, _} = line | _], :heading, :nested, _),
    do: {:start, 0, :ordered_list, :items, line}

  # A :list token is the start of a :bullet_list
  def run([{:list, _, _} = line | _], :heading, :nested, _),
    do: {:start, 0, :bullet_list, :items, line}

  # A :heading token is the start of a :heading
  def run([{:heading, _, desc} = line | _], :heading, :nested, [acc | _]) do
    %{options: %{level: line_level}} = desc
    %{options: %{level: current_level}} = acc
    if line_level > current_level, do: {:start, 1, :heading, :lines, line}, else: {:end, 0, acc}
  end

  def run(:eof, :heading, :nested, [acc | _]),
    do: {:end, 0, acc}

  ######## Bullet_list & Ordered_list

  # if the token is a :num (in a Ordered list) or a :list (in a :bullet_list), then compare the level of the current node with the level of the line
  def run([{tag, _, _} = line | _], state, _, [%{type: state, level: l} = acc | _])
      when (tag == :num and state == :ordered_list) or (tag == :list and state == :bullet_list) do
    # Identify the level of the line
    {_, _, %{options: %{level: l_line}}} = line

    # if it is the same level as the level of the ordered_list, start a new item. If the level is smaller, then end the list
    cond do
      l_line == l -> {:start, 1, tag, :lines, line}
      l_line < l -> {:end, 0, acc}
      l_line > l -> raise "should not be here/1"
    end
  end

  # if the token not a :num, then end the list
  def run(_, tag, _, [acc | _]) when tag in @list_types do
    {:end, 0, acc}
  end

  ######## Num & List
  # Stage :lines
  # if token == :line, accumulate lines
  def run([{:line, _, _} = line | _], num_or_list, :lines, [%{raw_lines: lines} = node | _])
      when num_or_list in @list_item_types do
    {:run, 1, %{node | raw_lines: lines ++ [line]}}
  end

  # for all other tokens, go to the next stage (:blocks)
  def run(_, num_or_list, :lines, [acc | _])
      when num_or_list in @list_item_types do
    {:end_stage, 0, :blocks,
     Map.put(acc, :joined_lines, join_lines_with_body(acc[:raw_lines], acc[:body]))}
  end

  # Stage :blocks
  # if token is a continueline, then enter a continued_list_of_blocks
  def run([{:continueline, _, _} = line | _], num_or_list, :blocks, _)
      when num_or_list in @list_item_types do
    {:start, 0, :continued_list_of_blocks, :blocks, line}
  end

  # if token is a num or a list, then we can either enter a nested list of end the node
  def run([{num_or_list1, _, _} = line | _], num_or_list2, :blocks, [
        %{level: l} = acc | _
      ])
      when num_or_list1 in @list_item_types and num_or_list2 in @list_item_types do
    # Identify the level of the line
    {_, _, %{options: %{level: l_line}}} = line

    # if it is a higher level as the level of the current num, enter a nested list (go to the next stage). Else end the node
    cond do
      l_line > l -> {:end_stage, 0, :nested, acc}
      l_line <= l -> {:end, 0, acc}
    end
  end

  # if token is anything else, end the stage
  def run(_, num_or_list, :blocks, [acc | _])
      when num_or_list in @list_item_types do
    {:end, 0, acc}
  end

  # Stage :nested
  def run([{num_or_list, _, _} = line | _], num_or_list, :nested, [
        %{level: l} = acc | _
      ])
      when num_or_list in @list_item_types do
    # Identify the level of the line
    {_, _, %{options: %{level: l_line}}} = line

    cond do
      l_line > l ->
        {:start, 0, @list_types_map[num_or_list], :items, line}

      l_line <= l ->
        {:end, 0, acc}
    end
  end

  def run([{:num, _, _} = line | _], :list, :nested, [
        %{level: l} = acc | _
      ]) do
    # Identify the level of the line
    {_, _, %{options: %{level: l_line}}} = line

    cond do
      l_line > l -> {:start, 0, @list_types_map[:num], :items, line}
      l_line <= l -> {:end, 0, acc}
    end
  end

  def run([{:list, _, _} = line | _], :num, :nested, [
        %{level: l} = acc | _
      ]) do
    # Identify the level of the line
    {_, _, %{options: %{level: l_line}}} = line

    cond do
      l_line > l -> {:start, 0, @list_types_map[:list], :items, line}
      l_line <= l -> {:end, 0, acc}
    end
  end

  # if token is anything else, end the node
  def run(_, num_or_list, :nested, [acc | _])
      when num_or_list in @list_item_types do
    {:end, 0, acc}
  end

  ######## Continued list of blocks

  def run([{:continueline, _, _} = line | _], :continued_list_of_blocks, _, _),
    do: {:start, 1, :literal, :line, line}

  # A :line token indicates the start of a :para
  def run([{:line, _, _} = line | _], :continued_list_of_blocks, _, _),
    do: {:start, 0, :para, :lines, line}

  # A :para token is also a :para, but with a tag
  def run([{:para, _, _} = line | _], :continued_list_of_blocks, _, _),
    do: {:start, 1, :para, :lines, line}

  # Verbatim block
  def run([{:verbatim, _, _} = line | _], :continued_list_of_blocks, _, _),
    do: {:start, 1, :verbatim, :lines, line}

  # quote and footnote and slot
  def run([{tag, _, _} = line | _], :continued_list_of_blocks, _, _)
      when tag in [:footnote, :quote],
      do: {:start, 1, tag, :nested, line}

  def run(_, :continued_list_of_blocks, _, [acc | _]) do
    {:end, 0, acc}
  end

  ####### Verbatim blocks

  # if token == :line, accumulate lines
  def run([{:line, _, _} = line | _], :verbatim, :lines, [%{raw_lines: lines} = para | _]) do
    {:run, 1, %{para | raw_lines: lines ++ [line]}}
  end

  # otherwise, there is only the possibility to be the end of the verbatim block
  def run([{:verbatim, _, desc} | _], :verbatim, :lines, [acc | _]) do
    {:end, 1, Map.put(acc, :closing_tag, desc)}
  end

  def run([{_, line_number, _} | _], :verbatim, :lines, [acc | _]) do
    {{:end, 0, acc}, {:error, {line_number, 0, line_number, 0}, :expecting_closing_verbatim}}
  end

  def run(:eof, :verbatim, :lines, [acc | _]) do
    {{:end, 0, acc}, {:error, :eof, :expecting_closing_verbatim}}
  end

  ### Utility function
  def join_lines(lines) do
    lines
    #    |> Enum.map(fn {_, _, line} -> line |> String.trim() end)
    |> Enum.map(fn {_, _, line} -> line |> String.trim_leading() end)
    |> Enum.join("\n")
  end

  def join_lines_with_body(lines, nil), do: join_lines(lines)

  def join_lines_with_body([_ | lines], body) do
    [{:line, nil, body} | lines]
    |> Enum.map(fn {_, _, line} -> line |> String.trim_leading() end)
    #    |> Enum.map(fn {_, _, line} -> line |> String.trim() end)
    |> Enum.join("\n")
  end

  def lshift(l, 0), do: l
  def lshift([_ | r], 1), do: r
end
