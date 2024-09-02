With _T As --_T = All tables with PK and their PK columns
(Select	T.object_id,
		Object_Schema_Name(T.object_id) Schm, 
		T.name Tbl,
		C.name Col,
		C.system_type_id,
		C.max_length,
		C.precision
From	sys.tables T
Inner Join sys.indexes I
		On T.object_id=I.object_id
		And I.index_id=1
Inner Join sys.index_columns IC
		On I.object_id=IC.object_id
		And I.index_id=IC.index_id
Inner Join sys.columns C
		On IC.object_id=C.object_id
		And IC.column_id=C.column_Id
Where	Exists (Select	*
				From	sys.objects O
				Where	O.type_desc='PRIMARY_KEY_CONSTRAINT'
						And O.parent_object_id=T.object_id)),
_T1 As --_T1 = All the tables with non FK columns, and their non-FK-columns
(Select	T1.object_id,
		Object_Schema_Name(T1.object_id) Schm, 
		T1.name Tbl,
		C1.name Col,
		C1.system_type_id,
		C1.max_length,
		C1.precision
From	sys.tables T1
Inner Join sys.columns C1
		On T1.object_id=C1.object_id
Where	Not Exists (Select	*
					From	sys.foreign_key_columns FKC1
					Where	FKC1.parent_object_id=C1.object_id
							And FKC1.parent_column_id=C1.column_id))
Select	Object_Schema_Name(T.object_id) PK_Schema,
		T.name PK_Table,
		Object_Schema_Name(T1.object_id) FK_Schema,
		T1.name FK_Table,
		CA.Cols,
		Concat('Alter Table [',Schema_Name(T1.schema_id),'].[',T1.name,'] Add Constraint [FK_',Schema_Name(T1.schema_id),'_',T1.name,'_',Replace(CA.Cols,',','_'),'] Foreign Key (',CA.Cols,') References [',Schema_Name(T.schema_id),'].[',T.name,'] (',CA.Cols,');') SQL
From	sys.tables T --Match all tables with PK
Inner Join sys.tables T1 --With tables with non-FK-columns 
		On T.object_id<>T1.object_id --But not a table with itself..
Cross Apply (Select	String_Agg(_T.Col,',') Cols
			From	_T
			Where	_T.object_id=T.object_id) CA
Where	1=1
		And Exists (Select	* --The condition that makes T "Tables with PK"
					From	_T
					Where	_T.object_id=T.object_id)
		And Exists (Select	* --The condition that makes T1 "Tables with non-FK-columns"
					From	_T1
					Where	_T1.object_id=T1.object_id)
		And Not Exists (Select	*	--So that all the PK columns on the "T" side will have matches with the same names and datatypes on the "T1" side:
									--Not exists in "T" side, columns that do not exist on the "T1" side..
						From	_T
						Where	_T.object_id=T.object_Id
								And Not Exists (Select	*
												From	_T1
												Where	_T1.object_id=T1.object_id
														And _T1.Col=_T.Col
														And _T1.system_type_id=_T.system_type_id
														And _T1.max_length=_T.max_length
														And _T1.precision=_T.precision))
		--And Object_Schema_Name(T.object_id)<>Object_Schema_Name(T1.object_id) --Optional condition: match only tables from the same schema
Order By 1,2;