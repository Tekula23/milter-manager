/* -*- c-file-style: "ruby" -*- */

#include "rb-milter-manager-private.h"

#define SELF(self) (MILTER_MANAGER_EGG(RVAL2GOBJ(self)))

static VALUE
initialize (VALUE self, VALUE name)
{
    G_INITIALIZE(self, milter_manager_egg_new(RVAL2CSTR(name)));
    return Qnil;
}

static VALUE
set_connection_spec (VALUE self, VALUE spec)
{
    GError *error = NULL;

    if (!milter_manager_egg_set_connection_spec(SELF(self),
						RVAL2CSTR(spec),
						&error))
	RAISE_GERROR(error);

    return Qnil;
}

static VALUE
merge (VALUE self, VALUE other)
{
    GError *error = NULL;

    if (!milter_manager_egg_merge(SELF(self), SELF(other), &error))
	RAISE_GERROR(error);

    return Qnil;
}

static VALUE
add_applicable_condition (VALUE self, VALUE condition)
{
    milter_manager_egg_add_applicable_condition(SELF(self),
						RVAL2GOBJ(condition));
    return Qnil;
}

static VALUE
get_applicable_conditions (VALUE self)
{
    const GList *conditions;

    conditions = milter_manager_egg_get_applicable_conditions(SELF(self));
    return GLIST2ARY((GList *)conditions);
}

static VALUE
clear_applicable_conditions (VALUE self)
{
    milter_manager_egg_clear_applicable_conditions(SELF(self));
    return Qnil;
}

static VALUE
to_xml (int argc, VALUE *argv, VALUE self)
{
    VALUE rb_indent;
    VALUE xml;
    GString *string;
    guint indent = 0;

    rb_scan_args(argc, argv, "01", &rb_indent);

    string = g_string_new(NULL);
    if (!NIL_P(rb_indent))
	indent = NUM2UINT(rb_indent);

    milter_manager_egg_to_xml_string(SELF(self), string, indent);
    xml = rb_str_new(string->str, string->len);
    g_string_free(string, TRUE);

    return xml;
}

void
Init_milter_manager_egg (void)
{
    VALUE rb_cMilterManagerEgg;

    rb_cMilterManagerEgg =
	G_DEF_CLASS(MILTER_TYPE_MANAGER_EGG, "Egg", rb_mMilterManager);

    G_DEF_SIGNAL_FUNC(rb_cMilterManagerEgg,
                      "to-xml", rb_milter_manager_gstring_handle_to_xml_signal);

    rb_define_method(rb_cMilterManagerEgg, "initialize", initialize, 1);

    rb_define_method(rb_cMilterManagerEgg,
		     "add_applicable_condition", add_applicable_condition, 1);
    rb_define_method(rb_cMilterManagerEgg,
		     "applicable_conditions", get_applicable_conditions, 0);
    rb_define_method(rb_cMilterManagerEgg,
		     "clear_applicable_conditions",
		     clear_applicable_conditions, 0);

    rb_define_method(rb_cMilterManagerEgg, "set_connection_spec",
		     set_connection_spec, 1);
    rb_define_method(rb_cMilterManagerEgg, "merge", merge, 1);
    rb_define_method(rb_cMilterManagerEgg, "to_xml", to_xml, -1);

    G_DEF_SETTERS(rb_cMilterManagerEgg);
}
