// Included in ShaderCompiler's texture-call code generation. GLSL ES 3.0
// requires constant sampler-array subscripts. Select the sampled value in a
// helper so the index and coordinate expressions are each evaluated once.
if (is_texture_func && RS::get_singleton()->is_low_end() && onode->arguments.size() > 1 &&
        onode->arguments[1]->type == SL::Node::NODE_TYPE_ARRAY) {
    const SL::ArrayNode *array = static_cast<const SL::ArrayNode *>(onode->arguments[1]);
    if (array->index_expression && array->index_expression->type != SL::Node::NODE_TYPE_CONSTANT &&
            shader->uniforms.has(array->name) && shader->uniforms[array->name].array_size > 0) {
        const int count = shader->uniforms[array->name].array_size;
        const String name = "hollow_sampler_select_" + itos(player_sampler_helper_id++);
        String parameters = "int hollow_index";
        String invocation = "int(" + _dump_node_code(array->index_expression, p_level, r_gen_code, p_actions, p_default_actions, false) + ")";
        String sample_arguments;
        for (int i = 2; i < onode->arguments.size(); i++) {
            const String argument = "hollow_arg_" + itos(i);
            parameters += ", " + _typestr(onode->arguments[i]->get_datatype()) + " " + argument;
            if (onode->arguments[i]->get_array_size() > 0) parameters += "[" + itos(onode->arguments[i]->get_array_size()) + "]";
            sample_arguments += ", " + argument;
            invocation += ", " + _dump_node_code(onode->arguments[i], p_level, r_gen_code, p_actions, p_default_actions, false);
        }
        String helper = _typestr(onode->get_datatype()) + " " + name + "(" + parameters + ") {\n";
        for (int i = 0; i < count; i++) {
            if (i < count - 1) helper += "if (hollow_index == " + itos(i) + ") ";
            helper += "return " + code + "(" + _mkid(array->name) + "[" + itos(i) + "]" + sample_arguments + ");\n";
        }
        helper += "}\n";
        player_sampler_helpers[current_func_name] += helper;
        code = name + "(" + invocation + ")";
        break;
    }
}
