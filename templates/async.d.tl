local record Async

{% macro lst(r, pfx) -%}
{%- for i in range(r) -%}{{pfx}}{{i+1}}{{ "," if not loop.last else ""}}
{%- endfor -%}
{%- endmacro %}

{% macro typ(a, r) -%}
{%- if r + a != 0 -%}
<
{{-lst(a, "A")-}}
{{- "," if a != 0 and r != 0 -}}
{{-lst(r, "R")-}}
>
{%- endif -%}
{%- endmacro -%}

{%- for a in range(0, 5) %}{% for r in range(0, 5) %}
  type fun{{a}}_{{r}} = function {{typ(a, r)}} ({{lst(a, "A")}}) :
{%- if r == 0 -%}
 ()
{%- else -%}
 {{lst(r, "R")}}
{%- endif %}
  void: function{{typ(a, r)}}(fun{{a}}_{{r}}{{typ(a, r)}}) : fun{{a}}_{{r}} {{typ(a, r)}}
  wrap: function
{{-typ(a, r)-}}
(function(
{{-lst(a, "A")-}}
{{-"," if a > 0-}}
function({{lst(r, "R")}})), integer) : fun{{a}}_{{r}} {{typ(a, r)}}
{% endfor %}{%- endfor %}

  run: function(function, function)

  record util
    sleep: function(integer)
    scheduler: function()
  end
end

return Async
