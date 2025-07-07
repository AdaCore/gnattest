# subprogram entry point.
#
# Usage as follows:
#   $ python decls_in_closure.py -P<prj> --subprogram <FILENAME>:<LINE>

import libadalang as lal
import argparse

from colorama import Fore
from colorama import Style
from itertools import chain

parser = argparse.ArgumentParser()
parser.add_argument("--project", "-P", type=str)
parser.add_argument(
    "--subprogram",
    help="Entry point for the analysis FILENAME:LINE",
    type=str,
    nargs="+",
)
parser.add_argument(
    "--file-output",
    help="where to write the list of all files that can be deleted",
    type=str,
)
parser.add_argument(
    "--subp-output",
    help="where to write the list of all subprograms that can be deleted (but not their containing file)",
    type=str,
)
args = parser.parse_args()

project = None
provider = None
if args.project:
    project = lal.GPRProject(args.project)
    provider = project.create_unit_provider()

context = lal.AnalysisContext(unit_provider=provider)

source_files = project.source_files()
units = [context.get_from_file(f) for f in source_files]
set_units = set(units)

# Get the filenames
for entry_point in args.subprogram:
    print(f"{Fore.GREEN} ======= Processing {entry_point} ======={Style.RESET_ALL}")
    (filename, line) = entry_point.split(":")
    unit = context.get_from_file(filename)
    for d in unit.diagnostics:
        print("{}: {}".format(filename, d))

    # Start by retrieving the entry point of the analysis
    entry_point = None
    if unit.root:
        for node in unit.root.finditer(
            lambda n: hasattr(n, "p_is_subprogram") and n.p_is_subprogram
        ):
            if node.sloc_range.start.line == int(line):
                print(f".... Found subprogram entry {node.p_fully_qualified_name}")
                entry_point = node

    # Then, build the call graph:
    #   * We have to retrieve all the calls
    #   * If they are dispatching, retrieve the overriding subprograms
    processed_decl = []

    def filter_none(lst):
        yield from (x for x in lst if x is not None)

    def filter_units(lst):
        yield from (n for n in lst if n.unit in set_units)

    def children_no_nested(node, depth=0):
        rec = False
        if node:
            rec = True
        if node and node.is_a(lal.BodyNode) and depth > 0:
            rec = False
        if rec:
            for n in filter_none(node.children):
                if n.is_a(lal.BaseId):
                    if n.p_is_direct_call:
                        yield n
                    else:
                        ref_decl = n.p_referenced_decl()
                        if ref_decl and (
                            ref_decl.is_a(lal.TaskTypeDecl)
                            or ref_decl.is_a(lal.BaseSubpBody) # Maybe a function pointer
                        ):
                            yield n
                elif n.is_a(lal.GenericInstantiation):
                    yield n
                yield from children_no_nested(n, depth + 1)

    def get_subp_body(node):
        # Return the SubpBody, TaskBody or ExprFunction corresponding to node,
        # if any, null otherwise.
        if node.is_a(lal.SubpRenamingDecl):
            return get_subp_body(node.f_renames.f_renamed_object.p_referenced_decl())
        elif node.is_a(lal.BaseSubpBody):
            return node
        elif node.is_a(lal.ClassicSubpDecl):
            return node.p_body_part_for_decl()
        elif node.is_a(lal.SubpBodyStub):
            return node.p_body_part_for_decl()
        elif node.is_a(lal.EntryDecl):
            # For a task entry decl, return the task body as an over approximation
            # TODO: replace p_next_part_for_decl once U920-016 if fixed.
            sempar = node.p_semantic_parent()
            if node.is_a(lal.SingleTaskTypeDecl):
                return sempar.parent.p_next_part_for_decl()
            elif node.is_a(lal.TaskTypeDecl):
                return sempar.p_next_part_for_decl()
            else:
                return node.p_body_part()
        elif node.is_a(lal.TaskTypeDecl):
            return node.p_next_part_for_decl()
        elif node.is_a(lal.BasicDecl):
            if node.p_is_subprogram:
                return node.p_body_part_for_decl()
        return None

    def get_body(node):
        if node.is_a(lal.GenericPackageInstantiation):
            return node.f_generic_pkg_name.p_referenced_decl()
        elif node.is_a(lal.GenericSubpInstantiation):
            return node.f_generic_subp_name.p_referenced_decl()
        elif node.is_a(lal.Name):
            return get_subp_body(node.p_referenced_decl())
        elif node.is_a(lal.BasicDecl):
            return get_subp_body(node)
        return None

    # Get the bodies from a call
    def bodies(name):
        if name.is_a(lal.Expr) and name.p_is_dispatching_call():
            root = name.p_referenced_decl().p_canonical_part()
            roots = root.p_root_subp_declarations()
            subp = root if not roots else roots[0]
            yield get_body(subp)
            yield from (get_body(s) for s in subp.p_find_all_overrides(units))
        else:
            yield get_body(name)

    def subp_reference_helper(body):
        for call in children_no_nested(body):
            yield from filter_none(filter_units(filter_none(bodies(call))))

    # Process a declaration, retrieving every reference to a subprogram,
    # be it a call or as a function pointer
    def get_subp_references(body):
        print(".... Processing " + body.p_fully_qualified_name)

        if body.is_a((lal.BodyNode, lal.GenericDecl)):
            yield from subp_reference_helper(body)
        return []

    subp_in_closure = {entry_point.unit: {entry_point}}
    processed_bodies = {entry_point}
    processed = set()

    while processed_bodies:
        for subp in get_subp_references(processed_bodies.pop()):
            if subp in processed:
                continue
            processed.add(subp)
            if subp.unit not in subp_in_closure or subp not in subp_in_closure[unit]:
                print("........ Found entry " + str(subp.p_fully_qualified_name))
                if subp.unit not in subp_in_closure:
                    subp_in_closure[subp.unit] = set()
                subp_in_closure[subp.unit].add(subp)
                processed_bodies.add(subp)

        # Now process all units, and retrieve anything that is a subprogram
        unit = context.get_from_file(filename)

    output_file = open(args.file_output, "w") if args.file_output else None
    output_subp = open(args.subp_output, "w") if args.subp_output else None

    # Check removal of units
    print(
        f"\n{Fore.GREEN} ======= Checking removal of units ======={Style.RESET_ALL}\n"
    )
    for unit in units:
        if unit not in subp_in_closure:
            # Check if there is a body that is in the closure if this is a unit
            # specification. In this case, we do not want to remove it.
            if unit.root.p_unit_kind == "unit_specification":
                other_part = unit.root.p_other_part
                if not other_part or (
                    other_part and other_part.unit not in subp_in_closure
                ):
                    print(
                        f"{Fore.RED}.. Unit {unit.filename} can be"
                        f" removed{Style.RESET_ALL}"
                    )
                    output_file.write(f"{unit.filename}\n")
            else:
                print(
                    f"{Fore.RED}.. Unit {unit.filename} can be removed{Style.RESET_ALL}"
                )
                output_file.write(f"{unit.filename}\n")

    # Check removal of subprograms
    print(
        f"\n{Fore.GREEN} ======= Checking removal of subprograms"
        f" ======={Style.RESET_ALL}\n"
    )

    for unit in units:
        if unit.root:
            # Whether the unit would completely disappear
            for node in unit.root.finditer(lambda n: n.is_a(lal.SubpBody)):
                if unit in subp_in_closure and node not in subp_in_closure[unit]:
                    print(
                        f"{Fore.RED}.. Procedure "
                        f"{node.p_fully_qualified_name} can be removed{Style.RESET_ALL}"
                    )
                    output_subp.write(f"{node.p_fully_qualified_name}\n")

    if output_file:
        output_file.close()
    if output_subp:
        output_subp.close()

    print(
        f"{Fore.GREEN} ======= Subprograms in closure of {entry_point} ======={Style.RESET_ALL}"
    )
    for unit, subprograms in subp_in_closure.items():
        print(f"{Fore.GREEN}.. In unit {unit.filename}{Style.RESET_ALL}")
        for subp in subprograms:
            print(".... " + str(subp))
