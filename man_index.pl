/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (c)  2018, VU University Amsterdam
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

:- module(prolog_manual_index,
          [ clean_man_index/0,          %
            save_man_index/0,
            index_man_directory/2,      % +DirSpec, +Options
            index_man_file/2,           % +Class, +FileSpec
                                        % Query
            current_man_object/1,       % ?Object
            man_object_property/2,      % ?Object, ?Property

            manual_object/5             % ?Obj, ?Summary, ?File, ?Class, ?Offset
          ]).
:- use_module(library(sgml)).
:- use_module(library(occurs)).
:- use_module(library(lists)).
:- use_module(library(filesex)).
:- use_module(library(error)).
:- use_module(doc_util).

/** <module> Index the HTML manuals

This module pre-processes the HTML files that constitute the manual such
that we can access the summary documentation of all predicates for usage
in IDE tools.
*/

:- predicate_options(index_man_directory/2, 2,
                     [ class(oneof([manual,packages,misc])),
                       pass_to(system:absolute_file_name/3, 3)
                     ]).


:- dynamic
    man_index/5.            % Object, Summary, File, Class, Offset

%!  manual_object(?Object, ?Summary, ?File, ?Class, ?Offset) is nondet.
%
%   True if Object is documented.  Arguments:
%
%   @arg Object is the object documented, described by a Prolog term.
%   Defined shapes are:
%
%     - section(Level, Number, Label, File)
%     - Name/Arity
%     - Name//Arity
%     - Module:Name/Arity
%     - Module:Name//Arity
%     - f(Name/Arity
%     - c(Name)
%
%   @arg Summary is a string object providing a summary of object
%   @arg File is the HTML file in which the object is documented
%   @arg Class is one of `manual` or `packages`
%   @arg Offset is the character offset at which the DOM element
%   describing Object appears.  This is used by doc_man.pl to
%   quickly extract the node.

manual_object(Object, Summary, File, Class, Offset) :-
    index_manual,
    man_index(Object, Summary, File, Class, Offset).

%!  clean_man_index is det.
%
%   Clean already loaded manual index.

clean_man_index :-
    retractall(man_index(_,_,_,_,_)).


%!  manual_directory(-Class, -Dir)// is nondet.
%
%   True if Dir is a directory holding manual files. Class is an
%   identifier used by doc_object_summary/4.

user:file_search_path(swi_man_manual,   swi('doc/Manual')).
user:file_search_path(swi_man_packages, swi('doc/packages')).

manual_directory(Class,   Dir) :-
    man_path_spec(Class, Spec),
    absolute_file_name(Spec, Dir,
                       [ file_type(directory),
                         access(read),
                         solutions(all)
                       ]).

man_path_spec(manual,   swi_man_manual(.)).
man_path_spec(packages, swi_man_packages(.)).


                 /*******************************
                 *          PARSE MANUAL        *
                 *******************************/

%!  save_man_index
%
%   Create swi('doc/manindex.db'), containing an  index   into  the HTML
%   manuals for use with help/1 and   similar predicates. This predicate
%   is called during the build process.

save_man_index :-
    man_index(_,_,_,_,_),
    !,
    save_index.
save_man_index :-
    index_manual.

%!  index_manual is det.
%
%   Load the manual index if not already done.

index_manual :-
    man_index(_,_,_,_,_),
    !.
index_manual :-
    with_mutex(pldoc_man,
               locked_index_manual).

locked_index_manual :-
    man_index(_,_,_,_,_),
    !.
locked_index_manual :-
    cached_index_file(read, File),
    catch(read_index(File), E,
          print_message(warning, E)),
    !.
locked_index_manual :-
    forall(manual_directory(Class, Dir),
           index_man_directory(Dir,
                               [ class(Class),
                                 file_errors(fail)
                               ])),
    catch(save_index, E,
          print_message(warning, E)).

%!  read_index(+File)
%
%   Read the manual index from File.

read_index(File) :-
    setup_call_cleanup(
        open(File, read, In, [encoding(utf8)]),
        read_man_index(In),
        close(In)).

read_man_index(In) :-
    read_term(In, Term, []),
    (   Term == end_of_file
    ->  true
    ;   valid_term(Term),
        assert(Term),
        read_man_index(In)
    ).

valid_term(Term) :-
    ground(Term),
    Term = man_index(_,_,_,_,_),
    !.
valid_term(Term) :-
    type_error(man_index_term, Term).

%!  save_index
%
%   Save the manual index to the file returned by cached_index_file/2.

save_index :-
    cached_index_file(write, File),
    !,
    Term = man_index(_,_,_,_,_),
    setup_call_cleanup(
        open(File, write, Out, [encoding(utf8)]),
        (   format(Out, '/*  Generated manual index.~n', []),
            format(Out, '    Do not edit.~n', []),
            format(Out, '*/~n~n', []),
            forall(Term, format(Out, '~q.~n', [Term]))
        ),
        close(Out)).
save_index.

cached_index_file(Access, File) :-
    absolute_file_name(swi('doc/manindex.db'), File,
                       [ access(Access),
                         file_errors(fail)
                       ]).


%!  check_duplicate_ids
%
%   Maintenance utility to check that we   do not have duplicate section
%   identifiers in the documentation.

:- public
    check_duplicate_ids/0.

check_duplicate_ids :-
    findall(Id, man_index(section(_,_,Id,_),_,_,_,_), Ids),
    msort(Ids, Sorted),
    duplicate_ids(Sorted, Duplicates),
    (   Duplicates == []
    ->  true
    ;   print_message(warning, pldoc(duplicate_ids(Duplicates)))
    ).

duplicate_ids([], []).
duplicate_ids([H,H|T0], [H|D]) :-
    !,
    take_prefix(H,T0,T),
    duplicate_ids(T, D).
duplicate_ids([_|T], D) :-
    duplicate_ids(T, D).

take_prefix(H, [H|T0], T) :-
    !,
    take_prefix(H, T0, T).
take_prefix(_, L, L).


%!  index_man_directory(Dir, +Options) is det
%
%   Index  the  HTML  directory   Dir.    Options are:
%
%           * class(Class)
%           Define category of the found objects.
%
%   Remaining Options are passed to absolute_file_name/3.

index_man_directory(Spec, Options) :-
    select_option(class(Class), Options, Options1, misc),
    absolute_file_name(Spec, Dir,
                       [ file_type(directory),
                         access(read)
                       | Options1
                       ]),
    atom_concat(Dir, '/*.html', Pattern),
    expand_file_name(Pattern, Files),
    maplist(index_man_file(Class), Files).


%!  index_man_file(+Class, +File)
%
%   Collect the documented objects from the SWI-Prolog manual file
%   File.

index_man_file(Class, File) :-
    absolute_file_name(File, Path,
                       [ access(read)
                       ]),
    debug(pldoc(man_index), 'Indexing ~p ~p', [Class, File]),
    open(Path, read, In, [type(binary)]),
    dtd(html, DTD),
    new_sgml_parser(Parser, [dtd(DTD)]),
    set_sgml_parser(Parser, file(File)),
    set_sgml_parser(Parser, dialect(sgml)),
    set_sgml_parser(Parser, shorttag(false)),
    nb_setval(pldoc_man_index, []),
    nb_setval(pldoc_index_class, Class),
    call_cleanup(sgml_parse(Parser,
                            [ source(In),
                              syntax_errors(quiet),
                              call(begin, index_on_begin)
                            ]),
                 (   free_sgml_parser(Parser),
                     close(In),
                     nb_delete(pldoc_man_index)
                 )).


%!  index_on_begin(+Element, +Attributes, +Parser) is semidet.
%
%   Called from sgml_parse/2 in  index_man_file/2.   Element  is the
%   name of the element, Attributes the  list of Name=Value pairs of
%   the open attributes. Parser is the parser objects.

index_on_begin(dt, Attributes, Parser) :-
    memberchk(class=pubdef, Attributes),
    get_sgml_parser(Parser, charpos(Offset)),
    get_sgml_parser(Parser, file(File)),
    sgml_parse(Parser,
               [ document(DT),
                 syntax_errors(quiet),
                 parse(content)
               ]),
    (   sub_term(element(a, AA, _), DT),
        member(Attr, ['data-obj', id, name]),
        memberchk(Attr=Id, AA),
        atom_to_object(Id, PI)
    ->  true
    ),
    nb_getval(pldoc_man_index, DD0),
    (   memberchk(dd(PI, File, _), DD0)
    ->  true
    ;   nb_setval(pldoc_man_index, [dd(PI, File, Offset)|DD0])
    ).
index_on_begin(dd, _, Parser) :-
    !,
    nb_getval(pldoc_man_index, DDList0), DDList0 \== [],
    nb_setval(pldoc_man_index, []),
    sgml_parse(Parser,
               [ document(DD),
                 syntax_errors(quiet),
                 parse(content)
               ]),
    summary(DD, Summary),
    nb_getval(pldoc_index_class, Class),
    reverse(DDList0, [dd(Object, File, Offset)|DDTail]),
    assertz(man_index(Object, Summary, File, Class, Offset)),
    forall(member(dd(Obj2,_,_), DDTail),
           assertz(man_index(Obj2, Summary, File, Class, Offset))).
index_on_begin(div, Attributes, Parser) :-
    !,
    memberchk(class=title, Attributes),
    get_sgml_parser(Parser, charpos(Offset)),
    get_sgml_parser(Parser, file(File)),
    sgml_parse(Parser,
               [ document(DOM),
                 syntax_errors(quiet),
                 parse(content)
               ]),
    dom_to_text(DOM, Title),
    nb_getval(pldoc_index_class, Class),
    swi_local_path(File, Local),
    assertz(man_index(section(0, '0', Local, File),
                      Title, File, Class, Offset)).
index_on_begin(H, Attributes, Parser) :- % TBD: add class for document title.
    heading(H, Level),
    get_sgml_parser(Parser, charpos(Offset)),
    get_sgml_parser(Parser, file(File)),
    sgml_parse(Parser,
               [ document(Doc),
                 syntax_errors(quiet),
                 parse(content)
               ]),
    dom_section(Doc, Nr, Title),
    nb_getval(pldoc_index_class, Class),
    section_id(Attributes, Title, File, ID),
    assertz(man_index(section(Level, Nr, ID, File),
                      Title, File, Class, Offset)).

section_id(Attributes, _Title, _, ID) :-
    memberchk(id=ID, Attributes),
    !.
section_id(_, "Bibliography", _, 'sec:bibliography') :- !.
section_id(_Attributes, Title, File, ID) :-
    atomic_list_concat(Words, ' ', Title),
    atomic_list_concat(Words, '_', ID0),
    atom_concat('sec:', ID0, ID),
    print_message(warning, pldoc(no_section_id(File, Title))).

%!  dom_section(+HeaderDOM, -NR, -Title) is semidet.
%
%   NR is the section number (e.g. 1.1, 1.23) and Title is the title
%   from a section header. The  first   clauses  processes the style
%   information from latex2html, emitting sections as:
%
%   ==
%   <HN> <A name="sec:nr"><span class='sec-nr'>NR</span>|_|
%                         <span class='sec-title'>Title</span>
%   ==

dom_section(DOM, Nr, Title) :-
    sub_term([ element(span, A1, [Nr]) | Rest ], DOM),
    append(_Sep, [element(span, A2, TitleDOM)], Rest),
    memberchk(class='sec-nr', A1),
    memberchk(class='sec-title', A2),
    !,
    dom_to_text(TitleDOM, Title).
dom_section(DOM, Nr, Title) :-
    dom_to_text(DOM, Title),
    section_number(Title, Nr, Title).

section_number(Title, Nr, PlainTitle) :-
    sub_atom(Title, 0, 1, _, Start),
    (   char_type(Start, digit)
    ->  true
    ;   char_type(Start, upper),
        sub_atom(Title, 1, 1, _, '.')       % A., etc: Appendices
    ),
    sub_atom(Title, B, _, A, ' '),
    !,
    sub_atom(Title, 0, B, _, Nr),
    sub_string(Title, _, A, 0, PlainTitle).

heading(h1, 1).
heading(h2, 2).
heading(h3, 3).
heading(h4, 4).


%!  summary(+DOM, -Summary:string) is det.
%
%   Summary is the first sentence of DOM.

summary(DOM, Summary) :-
    phrase(summary(DOM, _), SummaryCodes0),
    phrase(normalise_white_space(SummaryCodes), SummaryCodes0),
    string_codes(Summary, SummaryCodes).

summary([], _) -->
    !,
    [].
summary(_, Done) -->
    { Done == true },
    !,
    [].
summary([element(_,_,Content)|T], Done) -->
    !,
    summary(Content, Done),
    summary(T, Done).
summary([CDATA|T], Done) -->
    { atom_codes(CDATA, Codes)
    },
    (   { Codes = [Period|Rest],
          code_type(Period, period),
          space(Rest)
        }
    ->  [ Period ],
        { Done = true }
    ;   { append(Sentence, [C, Period|Rest], Codes),
          code_type(Period, period),
          \+ code_type(C, period),
          space(Rest)
        }
    ->  string(Sentence),
        [C, Period],
        { Done = true }
    ;   string(Codes),
        summary(T, Done)
    ).

string([]) -->
    [].
string([H|T]) -->
    [H],
    string(T).

space([C|_]) :- code_type(C, space), !.
space([]).

%!  dom_to_text(+DOM, -Text)
%
%   Extract the text of a parsed HTML term.  White-space in the
%   result is normalised.  See normalise_white_space//1.

dom_to_text(Dom, Text) :-
    phrase(cdata_list(Dom), CDATA),
    with_output_to(codes(Codes0),
                   forall(member(T, CDATA),
                          write(T))),
    phrase(normalise_white_space(Codes), Codes0),
    string_codes(Text, Codes).

cdata_list([]) -->
    [].
cdata_list([H|T]) -->
    cdata(H),
    cdata_list(T).

cdata(element(_, _, Content)) -->
    !,
    cdata_list(Content).
cdata(CDATA) -->
    { atom(CDATA) },
    !,
    [CDATA].
cdata(_) -->
    [].

%!  current_man_object(?Object) is nondet.

current_man_object(Object) :-
    index_manual,
    man_index(Object, _, _, _, _).

%!  man_object_property(?Object, ?Property) is nondet.
%
%   True when Property is a property of the given manual object. Defined
%   properties are:
%
%     - summary(-Text)
%     Summary text for the object.
%     - id(ID)
%     Return unique id for the text, so we can remove duplicates

man_object_property(Object, summary(Summary)) :-
    index_manual,
    man_index(Object, Summary, _, _, _).
man_object_property(Object, id(File-CharNo)) :-
    index_manual,
    man_index(Object, _, File, _, CharNo).

swi_local_path(Path, Local) :-
    atom(Path),
    is_absolute_file_name(Path),
    manual_root(RootSpec, Dir),
    absolute_file_name(RootSpec, SWI,
                       [ file_type(directory),
                         solutions(all)
                       ]),
    directory_file_path(SWI, ManLocal, Path),
    !,
    directory_file_path(Dir, ManLocal, Local).

manual_root(swi_man_manual(.),   'Manual').
manual_root(swi_man_packages(.), 'packages').