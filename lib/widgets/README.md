## About Widgets

A widget is a function that takes some arguments and outputs HTML tags to
`STDOUT`. Generally, a widget takes `name=value` arguments and uses them to set
up HTML element attributes of the tags it generates. The convention is to
pass on any attributes the widget doesn't care about to the main element the
widget generates. Some widgets such as `radio` and `selectbox` take further
positional arguments as well.

Some general rules about widgets:

- A widget's should usually have the `name` attribute set in order to be able
  to receive its value when it's clicked or when its value is changed.

- A widget's initial value, or, sometimes, the value to be used when the widget
  is "changed" (e.g., clicked, or selected), can be set via the `value` attribute.

  Upon receiving a change event from a widget, the widget's current value can
  be obtained via a global variable named `val_$name`, where `$name` is the widget's
  `name` attribute set at the widget function's invocation time.

  NOTE: In the case of a widget having multiple values, the `val_$name` variable
        will be an array.

- If a widget can have a label or some text associated with it, it's usually
  set with the `label` attribute.

- A widget also keeps track of its state so that when it's called in the
  presence of its "val" (`val_$name`) variable, it can render itself with the
  correct HTML outputs that reflect its current state.
