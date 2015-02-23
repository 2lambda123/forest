\newif\ifdraft
\drafttrue
%\draftfalse

\documentclass{sigplanconf}

% The following \documentclass options may be useful:

% preprint      Remove this option only once the paper is in final form.
% 10pt          To set in 10-point type instead of 9-point.
% 11pt          To set in 11-point type instead of 9-point.
% authoryear    To obtain author/year citation style instead of numeric.

\usepackage[utf8x]{inputenc}
\usepackage{amsmath, amsthm, amssymb, amsbsy}
\usepackage{microtype}
\usepackage[usenames,dvipsnames]{color}
\usepackage{caption}
\usepackage{graphicx}
\usepackage{hyperref}
\usepackage{thmtools}
\usepackage{wrapfig}
\usepackage{stmaryrd}
\usepackage{listings}
\usepackage{cancel}
\usepackage[all]{xy}

%%MnSymbol symbols
\DeclareFontFamily{U}{MnSymbolC}{}
\DeclareSymbolFont{MnSyC}{U}{MnSymbolC}{m}{n}
\DeclareFontShape{U}{MnSymbolC}{m}{n}{
    <-6>  MnSymbolC5
   <6-7>  MnSymbolC6
   <7-8>  MnSymbolC7
   <8-9>  MnSymbolC8
   <9-10> MnSymbolC9
  <10->   MnSymbolC10}{}
\DeclareMathSymbol{\smalltriangledown}{\mathop}{MnSyC}{75}
\DeclareMathSymbol{\diamondplus}{\mathop}{MnSyC}{124}
\DeclareMathSymbol{\diamondtimes}{\mathop}{MnSyC}{125}
\DeclareMathSymbol{\diamonddot}{\mathop}{MnSyC}{126}
\DeclareMathSymbol{\filledmedtriangleup}{\mathop}{MnSyC}{201}

\makeatletter
\newcommand{\pushright}[1]{\ifmeasuring@@#1\else\omit\hfill$\displaystyle#1$\fi\ignorespaces}
\newcommand{\pushleft}[1]{\ifmeasuring@@#1\else\omit$\displaystyle#1$\hfill\fi\ignorespaces}
\makeatother

%include polycode.fmt

\ifdraft
\newcommand{\hugo}[1]{{\color{red} [#1]}}
\else
\newcommand{\hugo}[1]{}
\fi

\theoremstyle{theorem}
\newtheorem{proposition}{Proposition}
\theoremstyle{theorem}
\newtheorem{theorem}{Theorem}[section]
\theoremstyle{theorem}
\newtheorem{definition}{Definition}[section]
\theoremstyle{definition}
\newtheorem{lemma}{Lemma}

\begin{document}

\special{papersize=8.5in,11in}
\setlength{\pdfpageheight}{\paperheight}
\setlength{\pdfpagewidth}{\paperwidth}

\conferenceinfo{CONF 'yy}{Month d--d, 20yy, City, ST, Country} 
\copyrightyear{20yy} 
\copyrightdata{978-1-nnnn-nnnn-n/yy/mm} 
\doi{nnnnnnn.nnnnnnn}

% Uncomment one of the following two, if you are not going for the 
% traditional copyright transfer agreement.

%\exclusivelicense                % ACM gets exclusive license to publish, 
                                  % you retain copyright

%\permissiontopublish             % ACM gets nonexclusive license to publish
                                  % (paid open-access papers, 
                                  % short abstracts)

%\titlebanner{banner above paper title}        % These are ignored unless
%\preprintfooter{short description of paper}   % 'preprint' option specified.

\title{TxForest: Composable Memory Transactions over Filestores}

\authorinfo{Forest Team}
           {Cornell, TUFTS}
           {forest@@cs.cornell.edu}
\maketitle

\begin{abstract}

\end{abstract}

%\category{CR-number}{subcategory}{third-level}

%\terms
%term1, term2

\keywords

%include formatting.lhs

\section{Introduction}

Databases are a long-standing, effective technology for storing structured and semi-structured data. Using a database has many benefits, including transactions and access to rich set of data manipulation languages and toolkits.

downsides: heavy legacy, relational model is not always adequate

cheaper and simpler alternative: store data directly as a collection of files, directories and symbolic links in a traditional filesystem.

examples of filesystems as databases

filesystems fall short for a number of reasons

Forest~\cite{forest} made a solid step into solving this, by offering an integrated programming environment for specifying and managing filestores.

Although promising, the old Forest suffered two essential shortcomings:
\begin{itemize}
	\item It did not offer the level of transparency of a typical DBMS. Users don't get to believe that they are working directly on the database (filesystem). they explicitly issue load/store calls, and instead manipulate in-memory representations and the filesystem independently. offline synchronization.
	\item It provided none of the transactional guarantees familiar from databases. transactions are nice: prevent concurrency and failure problems. successful transactions are guaranteed to run in serial order and failing transactions rollback as if they never occurred. rely on extra programmers' to avoid the hazards of concurrent updates. different hacks and tricks like creating lock files and storing data in temporary locations, that severely increase the complexity of the applications. writing concurrent programs is notoriously hard to get right. even more in the presence of laziness (original forest used the generally unsound Haskell lazy I/O)
\end{itemize}


transactional filesystem use cases:

a directory has a group of files that must be processed and deleted and having the aggregate result written to another file.

software upgrade (rollback),

concurrent file access (beautiful account example?)

Specific use cases:
LHC\\
Network logs\\
Dan's scientific data



\section{Examples}

\section{The Forest Language}

the forest description types

a forest description defines a structured representation of a semi-structured filestore.

each Forest declaraction is interpreted as:
an expected on-disk shape of a filesystem fragment
a transactional variable
an ordinary Haskell type for the in-memory representation that represents the content of a variable

two expression quotations: non-monadic |(e)| vs monadic |<||e||>|

|FileInfo| for directories/files/symlinks.

\begin{figure}
\begin{spec}
[pads| data Balance = Balance Int |]

[forest|
	type Accounts = [ a :: Account | a <- matches (GL "*") ]
	type Account = File Balance
|]
\end{spec}
\label{fig:accounts}
\end{figure}

\begin{figure}
\begin{spec}

data Balance = ...
type Balance_md = ...

data Accounts
instance TxForest () Accounts (FileInfo,[(FilePath,Account)]) where ...

data Account
instance TxForest () Account ((FileInfo,Balance_md),Balance) where ...
\end{spec}
\label{fig:accountsHaskell}
\end{figure}

\begin{figure}
\begin{spec}
[forest|
	type Universal_d = Directory 
             { ascii_files  is [ f :: TextFile     | f <- matches (GL "*"), (kind  f_att == AsciiK) ]
             , binary_files is [ b :: BinaryFile   | b <- matches (GL "*"), (kind  b_att == BinaryK) ]
             , directories  is [ d :: Universal_d  | d <- matches (GL "*"), (kind  d_att == DirectoryK) ]
             , symlinks     is [ s :: Link         | s <- matches (GL "*"), (isJust (symLink s_att)) ]
             }
|]
\end{spec}
\label{fig:universal}
\end{figure}

\section{Forest Transactions}

The Forest description language introduced in the previous section describes how to specify the expected shape of a filestore as an allegorical Haskell type, independently from the concrete programming artifacts that are used to manipulate such filestores.
We now focus on the key goal of this paper: the design of the Transactional Forest interface.

As we shall see, TxForest (for short) offers an elegant and powerful abstraction to concurrently manipulate structured filestores.
We first describe general-purpose transactional facilities~(\ref{subsec:composable}).
We then introduce transactional forest variables that allow programmers to interact with filestores~(\ref{subsec:tvars}).
We briefly touch on how programmers can verify, at any time, if a filestore conforms to its specification~(\ref{subsec:validation}), and finish by introducing filestore-analogous versions of standard file system operations~(\ref{subsec:fsops}).

\subsection{Composable transactions}
\label{subsec:composable}

As an embedded domain-specific language in Haskell, the inspiration for TxForest is the widely popular \emph{software transactional memory} (\texttt{STM}) Haskell library, that provides a small set of highly composable operations to define the key facilities of a transaction. We now explain the intuition of each one of these mechanisms, cast in the context of TxForest.

\paragraph{Running transactions}

In TxForest, one runs a transaction by calling an |atomic| function with type:\footnote{For the original \texttt{STM} interface, substitute |FTM| by |STM|~\cite{HaskellSTM}.}
\begin{spec}
	atomic :: FTM a -> IO a
\end{spec}
It receives a forest memory transaction, of type |FTM a|, and produces an |IO a| action that executes the transaction atomically with respect to all other concurrent transactions, returning a result of type |a|.
In the pure functional language Haskell, |FTM| and |IO| are called monads. Different monads are typically used to characterize different classes of computational effects.
|IO| is the primitive Haskell monad for performing irrevocable I/O actions, including reading/writing to files or to mutable references, managing threads, etc.
For example, the Haskell prelude functions:
\begin{spec}
	getChar :: IO Char
	putChar :: Char -> IO ()
\end{spec}
respectively read a character from the standard input and write a single character to the standard output.

Conversely, our |FTM| monad denotes computations that are tentative, in the sense that they happen inside the scope of a transaction and can always be rolled back.
As we shall in the remainder of this section, these consist of STM-like transactional combinators, file system operations on Forest filestores, or arbitrary pure functions.
Note that, being |FTM| and |IO| different types, the Haskell type system effectively prevents non-transactional actions to be run inside a transaction. This is a valuable guarantee, and one that is not commonly found in transactional libraries for mainstream programming languages without a very expressive type system.

\paragraph{Blocking transactions}

To allow a transaction to \emph{block} on a resource, TxForest provides a single |retry| operation with type:
\begin{spec}
retry :: FTM a
\end{spec}
Conceptually, |retry| cancels the current transaction, without emitting any errors, and schedules it to be retried at a later time.
Since each transaction logs all the reads/writes that it performs on a filestore, an efficient implementation waits for another transaction to update the shared filestore fragments read by the blocked transaction before retrying.

Using |retry| we can define a pattern for conditional transactions that wait on a condition to be verified before performing an action:
\begin{spec}
wait :: FTM Bool -> FTM a -> FTM a
wait b c a = do { b <- p ; if b then retry else a }
\end{spec}

All of the reads in a transaction are logged and when |retry| is called,
it blocks until another transaction writes to a file from the read log before restarting the
transaction from scratch.

\paragraph{Composing transactions}

Multiple transactions can be sequentially composed via the standard |do| notation. For example, we can write:
\begin{spec}
	do { x <- ftm1; fmt2 x }
\end{spec}
to run a transaction |ftm1 : FTM a| and pass its result to a transaction |ftm2 :: a -> FTM b|. Since the whole computation is itself a transaction, it will be performed indivisibly inside an |atomic| block.

We can also compose transactions as \emph{alternatives}, using the |orElse| primitive:
\begin{spec}
	orElse :: FTM a -> FTM a -> FTM a
\end{spec}
This combinator performs a left-biased choice: it first runs transaction |ftm1|, tries |fmt2| if |ftm1| retries, and the whole action retries if |ftm2| retries.
It can be useful, for example, to read either one of two files depending on the current configuration of the file system.

Note that |orElse| provides an elegant mechanism to define nested transactions. At any point inside a larger transaction, we can tentatively perform a transaction |ftm1|, and rollback to the beginning (of the nested transaction) to try an alternative |ftm2| in case |fmt1| retries:
\begin{spec}
do { ... ; orElse ftm1 ftm2; ... }
\end{spec}

\paragraph{Exceptions}

The last general-purpose feature of |FTM| transactions are \emph{exceptions}. In Haskell, both built-in and user-defined exceptions are used to signal error conditions. We can |throw| and |catch| exceptions in the |FTM| monad in the same way as the |IO| monad:
\begin{spec}
	throw :: Exception e => e -> FTM a
	catch :: Exception e => FTM a -> (e -> FTM a) -> FTM a
\end{spec}

For instance, a TxForest user may define a new |FileNotFound| exception and write the following pseudo-code:
\begin{spec}
tryRead = do
	{ exists <- ...find file...
	; if (not exists) then throw FileNotFound else return ()
	; ...read file... }
\end{spec}
If the file in question is not found, then a |FileNotFound| exception is thrown, aborting the current |atomic| block (and hence the file is never read).
Programmers can prevent the transaction from being aborted, and its effects discarded, by catching exceptions inside the transaction, e.g.:
\begin{spec}
	catch tryRead (\FileNotFound -> return ...default...) tryRead
\end{spec}

\subsection{Transactional variables}
\label{subsec:tvars}

We have seen how to build transactions from smaller transactional blocks, but we still haven't seen concrete operations to manipulate \emph{shared data}, a fundamental piece of any transactional mechanism.
In vanilla Haskell STM, communication between threads is done via shared mutable memory cells called \emph{transactional variables}.
For a transaction to log all memory effects, transactional variables can only be explicitly created, read from or written to using specific transactional operations. Nevertheless, Haskell programmers can traverse, query and manipulate the content of transactional variables using the rich language of purely functional computations; since these don't have side-effects, they don't ever need to be logged or rolled back.

In the context of TxForest, shared data is not stored in-memory but on the filestore. It is illuminating to quote~\cite{HaskellSTM}:
\begin{quote}
``We study internal concurrency between threads interacting through memory [...]; we do not consider here the questions of external interaction through storage systems or databases.''
\end{quote}
We consider precisely the question of external interaction with a file system.
Two transactions may communicate, e.g., by reading from or writing to the same file or possibly a list of files within a directory.
To facilitate this interaction, the TxForest compiler generates an instance of the |TxForest| type class (and corresponding types) for each Forest declaration:
\begin{spec}
class TxForest args ty rep | ty -> rep, ty -> args where
	new             ::  args -> FilePath -> FTM fs ty
	read            ::  ty -> FTM rep
	writeOrElse     ::  ty -> rep -> b
	                -> (Manifest -> FTM fs b) ->  FTM fs b
\end{spec}
In this signature, |ty| is an opaque transactional variable type that uniquely identifies a user-declared Forest type. The representation type |rep| is a plain Haskell type that holds the content of a transactional variable. The representation type closely follows the declared Forest type, with additional file-content metadata for directories, files and symbolic links; directories have representation of type |(FileInfo,dir_rep)| and basic types have representation of type |((FileInfo,base_md),base_rep)|, for base representation |base_rep| and metadata |based_md|.

\paragraph{Creation}
The transactional forest programing style draws no distinction between data on the file system and in-memory.
Anywhere inside a transaction, users can declare a |new| transactional variable, with argument data pertaining to the forest declaration and rooted at the argument path in the file system.
This operation does not have any effect on the file system, and just establishes the schema to which a filestore should conform.

\paragraph{Reading}
Users can |read| data from a filestore by reading the contents of a transactional variable.
Imagine that we want to retrieve the balance of a particular account from a directory of accounts as specified in Figure~\ref{fig:accounts}:
\begin{spec}
do
	accs :: Accounts <- new () "/var/db/accounts"
	(accs_info,accs_rep) <- read accs
	let acc1 :: Account = fromJust (lookup "account1" accs_rep)
	((acc1_info,acc1_md),Balance balance) <- read acc1
	return balance
\end{spec}
The corresponding generated Haskell functions and types appear in Figure~\ref{fig:accountsHaskell}.
In the background, this is done by lazily traversing the directories, files and symbolic links mentioned in the top-level forest description. The second line reads the accounts directory and generates a list of accounts, that can be manipulated with standard list operations to find the respective account.
An account is itself a transactional variable, that can be read in the same way. Note that the file holding the balance of |"account1"| is only read in the fourth line.
The type signatures elucidate the type of each transactional variable.

Programmers can control the degree of laziness in a forest description by adjusting the granularity of Forest declarations.
For instance, if we have chosen to inline the type of |Account| in the description as:
\begin{spec}
[forest|
	type Accounts = [ a :: File Balance | a <- matches (GL "*") ]
|]
\end{spec}
then reading the accounts directory would also read the file content of all accounts, since the balance of each account would not be encapsulated behind a transactional variable.

\paragraph{Writing}
Users can modify a filestore by writing new content to a transactional variable.
The |writeOrElse| function accepts additional arguments to handle possible conflicts, that arise due to data dependencies in the Forest description that cannot be statically checked by the type system -- if these dependencies are not met, the data is not a valid representation of a filestore.
If the write succeeds, the file system is updated with the new data and a default value of type |b| is returned.
If the write fails, a user-supplied alternate function is executed instead; users are replied with a |Manifest| describing the tentative modifications to the file system and a report of the inconsistencies.
We can easily define more convenient derived forms of |writeOrElse|:
\begin{spec}
-- optional write
tryWrite :: TxForest args ty rep => ty -> rep -> FTM ()
tryWrite t v = writeOrElse t v () (const (return ()))
-- write or restart the transaction
writeOrRetry :: TxForest args ty rep => ty -> rep -> () -> FTM ()
writeOrRetry t v = writeOrElse t v () (const retry)
-- write or yield an error
writeOrThrow :: (TxForest args ty rep,Exception e) => ty -> rep -> () -> e -> FTM ()
writeOrThrow t v e = writeOrElse t v () (const (throw e))
\end{spec}
A typical example of an inconsistent representation is when a Forest description refers to the same file twice and the user attempts to write distinct file content in each occurrence. For instance, in the universal description of Figure~\ref{fig:universal} a symbolic link to an ASCII file in the same directory is mapped both under the |ascii_files| and |symlinks| fields.

Writes take immediate effect on the (transactional snapshot of the) filestore, meaning that any subsequent |read| will see the performed modifications. Within a transaction, there can be multiple variables (possibly of different types) connected to the same fragment of a file system. Consider the following example with two accounts pointing to the same file path:
\begin{spec}
	acc1 :: Account <- new () "/var/db/accounts/account"
	acc2 :: Account <- new () "/var/db/accounts/account"
	(acc_md,Balance balance) <- read acc1
	tryWrite acc2 (acc_md,Balance (balance + 1)) 
	(acc_md',Balance balance') <- read acc1
\end{spec}
By incrementing the balance of |acc2|, we are implicitly incrementing the balance of |acc1| (if the write succeeds, then |balance' = balance + 1|).

\subsection{Validation}
\label{subsec:validation}

As Forest lays a structured view on top a semi-structured file system, a filestore does not need to conform perfectly to an associated Forest description.
Behind the scenes, TxForest lazily computes a summary of such discrepencies. These may flag, for example, that a mandatory file does not exist or an arbitrarily complex user-defined Forest constraint is not satisfied.
Validation is not performed unless explicitly demanded by the user. At any point, a user can |validate| a transactional variable and its underlying filestore:
\begin{spec}	
	validate :: TxForest args ty rep => ty -> FTM ForestErr
\end{spec}
The returned |ForestErr| reports a top-level error count and the topmost error message:
\begin{spec}
	data ForestErr = ForestErr
		{  numErrors  :: Int
		,  errorMsg   :: Maybe ErrMsg }
\end{spec}

We can always make validation mandatory and validation errors fatal by encapsulating any error inside a |ForestError| exception:
\begin{spec}
validRead :: TxForest args ty rep => ty -> FTM rep
validRead ty = do
	rep <- read ty
	err <- validate ty
	if numErrors err == 0
		then return rep
		else throw (ForestError err)
\end{spec}

\subsection{Standard file system operations}
\label{subsec:fsops}

To better understand the TxForest interface, we now discuss how to perform common operations on a Forest filestore.

\paragraph{Creation/Deletion}
Given that validation errors are not fatal, a |read| always returns a (nevertheless valid) representation. For example, if a user tries to read the balance of an inexistent account:
\begin{spec}
do
	badAcc :: Account <- new () "/var/db/accounts/account"
	(acc_info,Balance balance) <- read badAcc
\end{spec}
then |acc_info| will hold invalid file information and |balance| a default value (implemented as |0| for |Int| values).
Perhaps less intuitive is how to create a new account; we create a new variable (that if read would hold default data) and write new valid file information and an arbitrary balance:
\begin{spec}
newAccount path balance = do
	newAcc :: Account <- new () path
	tryWrite newAcc (validFileInfo path,Balance balance)
\end{spec}
Deleting an account is dual; we write invalid file information and the default balance to the corresponding variable:
\begin{spec}
delAcccount acc = do
	tryWrite acc (invalidFile,Balance 0)
\end{spec}
The takeaway lesson is that the |FileInfo| metadata actually determines whether a directory, file or symbolic link exists or not in the file system, since we cannot infer that from the data alone (e.g., an empty account has the same balance has an inexistent account).
This also reveals less obvious data dependencies: for valid paths the |fullpath| in the metadata must match the path to which the representation corresponds in the description, and for invalid paths the representation data must match the Forest-generated default data.
Since this can become cumbersome to ensure manually, we provide a general function that conveniently removes a filestore, named after the POSIX \verb|rm| operation:
\begin{spec}
rm :: TxForest args ty rep => ty -> FTM ()
\end{spec}

\paragraph{Copying}

A user can copy an account from a source path to a target path as follows:
\begin{spec}
copyAccount srcpath tgtpath = do
	src :: Account <- new () srcpath
	tgt :: Account <- new () tgtpath
	(info,balance) <- read src
	tryWrite tgt (info { fullpath = tgtpath },balance)
\end{spec}
The pattern is to create a variable for each path, and copy the content with an updated |fullpath|.
Copying a directory of accounts follows the same pattern but is more complicated, in that we also have to recursively copy underlying accounts and update all the metadata accordingly.
Therefore, we provide an analogous to the POSIX \verb|cp| operation that attempts to copy the content of a filestore into another:
\begin{spec}
cpOrElse  ::  TxForest args ty rep => ty -> ty -> b
          ->  (Manifest -> rep -> FTM fs b) -> FTM fs b
\end{spec}
Unlike |rm|, |copyOrElse| is only a best-effort operation that may fail due to arbitrarily complex data dependencies in the Forest description. Such dependencies necessarily hold in the source representation for the source arguments but may not for the target arguments.
Similarly to |writeOrElse|, we provide |tryCopy|, |copyOrRetry| and |copyAndThrow| operations with the expected type signatures.

For an example of what might go wrong while copying, consider the following description for accounts parameterized by a template name:
\begin{spec}
	[forest|
		type NameAccounts (acc :: String) = [ a :: Account | a <- matches (GL (acc ++ "*")) ]
	|]
\end{spec}
This specification has an implicit data dependency that all the account files listed in the in-memory representation have name matching the Glob pattern.
Thus, trying to copy between filestores with different templates would effectively fail, as in:
\begin{spec}
do
	src :: Accounts <- new "account" "/var/db/accounts"
	tgt :: Accounts <- new "acc" "/var/db/accs"
	tryCopy src tgt 
\end{spec}

\section{Implementation}

We now delve into how Transactional Forest can be efficiently implemented.
The current implementation is available from the project website (\url{forestproj.org) and is done completely in Haskell.



increasing levels of incremental support, and added complexity.

%read-only vs read-write: we only allow read-only expressions in Forest specifications.
%we need to have data/medata under the same variable because we issue stores on variable writes: writeData rep >> writeMeta md /= write (rep,md)

\subsection{Transactional Forest}

\emph{optimistic concurrency control}

(this is important since we write to canonical paths, whose canonicalization may depend on concurrent writes...)

lock-free lazy acquire
acquire ownership. only one tx can acquire an object at a time.
global total order on variables, acquire variables in sorted order
the analogous in txforest would be per-filepath locks, what does nto work out-of-the-box in the presence of symbolic links

the identity of a filepath is not unique (different paths point to the same physical address) nor stable (equivalence depends on on the current filesystem).

transactional semantics of STM: we log reads/writes to the filesystem instead of variables. global lock, no equality check on validation.
load/store semantics of Forest with thunks, explicit laziness

transactional variables created by calling load on its spec with given arguments and root path; lazy loading, so no actual reads occur.
Additionally to the representation data, each transactional variable remembers its creation-time arguments (they never change).


each transaction keeps a local filesystem version number, and a per-tvar log mapping fsversions to values, stored in a weaktable (fsversions are purgeable once a tx commits).

on writes: backup the current fslog, increment the fsversion, add an entry to the table for the (newfsversion,newvalue), run the store function for the new data and writing the modifications to the buffered FS; if there are errors, rollback to the backed-up FS and the previous fsversion.

the store function also changes the in-memory representation by recomputing the validation thunks (hidden to users) to match the new content.

write success theorem: if the current rep is in the image of load, then store succeeds

\subsection{Incremental Transactional Forest}

problem with 1st approach: ic loading: two variables over the same file; read spec1, write spec2, read spec1 (our simple cache mechanism fails to prevent recomputation)
laziness problem with 1st approach: ic storing: read variable (child variables are lazy), write variable (will recursively store everything); instead of no-op!


exploit DSL information to have incrementality

\subsection{Log-structured Transactional Forest}

problem with 2nd approach: tx1 reads a variable; tx2 reads the same variable

exploit (DSL info +) FS support to have incrementality

read-only transactions require no synchronization

\section{Evaluation}

although Haskell is a great language laboratory, we are already paying a severe performance overhead if efficiency is the only concern.

even the Haskell STM is implemented in C

\section{Related Work}


transactional filesystems (user-space vs kernel-space)
\url{http://www.fuzzy.cz/en/articles/transactional-file-systems}\\
\url{http://www.fsl.cs.sunysb.edu/docs/valor/valor_fast2009.pdf}\\
\url{http://www.fsl.cs.sunysb.edu/docs/amino-tos06/amino.pdf}

libraries for transactional file operations:
\url{http://commons.apache.org/proper/commons-transaction/file/index.html}\\
\url{https://xadisk.java.net/}\\
\url{https://transactionalfilemgr.codeplex.com/}

tx file-level operations (copy,create,delete,move,write)
schema somehow equivalent to using the unstructured universal Forest representation

but what about data manipulation: transactional maps,etc?

\section{Conclusions}

transactional variables do not descend to the content of files. pads specs are read/written in bulk. e.g., append line to log file. extend pads.

\bibliographystyle{abbrvnat}
\bibliography{forest}

\onecolumn
\appendix

\section {Forest Semantics}

\begin{align*}
	&|(star F (r/u)) = | \left\{
	\begin{array}{ll}
		|star F (prime r)| & \quad \text{if}~ |app F ((star F r) / u) = (i,Link (prime r))| \\
		|(star F r) / u| & \quad \text{otherwise}
	\end{array} \right. \\
	&|(star F cpath) = cpath|
\end{align*}

\begin{displaymath}
	\frac{}{|r `inSet` cpath|}
	\quad
	\frac{}{|r `inSet` r|}
	\quad
	\frac{|r `inSet` (prime r)|}{|r / u `inSet` (prime r)|}
\end{displaymath}

\begin{align*}
	|focusF F r `def`| F ||_{|{forall (prime r) (star F (prime r) `inSet` r)}|}
\end{align*}

\begin{spec}
	eqUnder F rs (prime F) = forin r rs (focusF F r = focusF (prime F) r)
\end{spec}

\begin{spec}
	Err a = (M Bool,a)
\end{spec}

\begin{tabular}{l||l||l}
	|s|			& |R s| & |C s| \\
	\hline
	|M s|		& |M (Err (R s))| & |M (Err (R s))| \\
	$k_{\tau_1}^{\tau_2}$ & |Err (tau2,tau1)| & |(tau2,tau1)| \\
	|e :: s|	& |R s| & |C s| \\
	|dpair x s1 s2| & |Err (R s1,R s2)| & |(C s1,C s2)| \\
	|flist s x e| & |Err [R s]| & |[C s]| \\
	|P(e)|		& |Err ()| & |()| \\
	|s?|		& |Err (Maybe (R s))| & |Maybe (C s)|
\end{tabular}

|R| is the internal in-memory representation type of a forest declaration;
|C| is the external type of content of a variables that users can inspect/modify

\begin{spec}
	app err a = doM { e <- getM a; (aerr,v) <- e; returnM aerr }
	app err (aerr,v) = returnM aerr
	
	app valid v = doM { aerr <- err v; eerr <- getM aerr; eerr }
\end{spec}

|v1 (sim oenv1 oenv2) v2| denotes value equivalence modulo memory addresses, under the given environments.
|e1 (sim oenv1 oenv2) e2| denotes expression equivalence by evaluation modulo memory addresses, under the given environments.

|v1 (simErr oenv1 oenv2) v2| denotes value equivalence (ignoring error information) modulo memory addresses, under the given environments.

$\boxed{|load oenv eenv r s F (prime oenv) v|}$ ``Under heap |oenv| and environment |eenv|, load the specification |s| for filesystem |F| at path |r| and yield a representation |v|.''

$\boxed{|s = M s1|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		a \notin |dom (oenv)| \quad |aerr `notin` dom oenv| \quad |e = pload eenv r (M s) F | \\
		|eerr = doM { e1 <- getM a; v1 <- e1; valid v1 }|
	\end{array}
	}{
		|load oenv eenv r (M s) F (extoenv2 oenv aerr eerr a e) (aerr,a)|
	}
\end{displaymath}

$\boxed{|s = k|}$

\begin{displaymath}
	\frac{
		|aerr `notin` dom oenv| \quad |meval oenv (loadk k eenv F r) (prime oenv) (b,v)| \quad
	}{
		|load oenv eenv r k F (extoenv (prime oenv) aerr (returnM b)) (aerr,v)|
	}
\end{displaymath}

\begin{displaymath}
	 |loadk File eenv F r| \left\{
	\begin{array}{ll}
		|returnM (True,(i,u))| & \quad \text{if}~ |app F (r) = (i,File u)| \\
		|returnM (False,(iinvalid,""))| & \quad \text{otherwise}
	\end{array} \right.
\end{displaymath}

\begin{displaymath}
	 |loadk Dir eenv F r| \left\{
	\begin{array}{ll}
		|returnM (True,(i,us))| & \quad \text{if}~ |app F (r) = (i,Dir us)| \\
		|returnM (False,(iinvalid,{}))| & \quad \text{otherwise}
	\end{array} \right.
\end{displaymath}

\begin{displaymath}
	 |loadk Link eenv F r| \left\{
	\begin{array}{ll}
		|returnM (True,(i,prime r))| & \quad \text{if}~ |app F (r) = (i,Link (prime r))| \\
		|returnM (False,(iinvalid,cpath))| & \quad \text{otherwise}
	\end{array} \right.
\end{displaymath}

$\boxed{|s = e :: s1|}$

\begin{displaymath}
	\frac{
		|meval oenv (sem (r / e) eenv Path) (prime oenv) (prime r)| \quad 
		|load oenv eenv (prime r) s F (prime2 oenv) v|
	}{
		|load oenv eenv r (e :: s) F (prime2 oenv) v|
	}
\end{displaymath}

$\boxed{|s = dpair x s1 s2|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|load oenv eenv r s1 F oenv1 v1| \\
		|load oenv1 (exteenv eenv x v1) r s2 F oenv2 v2|\\
		|eerr = doM { b1 <- app valid v1; b2 <- app valid v2; returnM (b1 `and` b2) } |
	\end{array}
	}{
		|load oenv eenv r (dpair x s1 s2) F (extoenv oenv2 aerr eerr) (aerr,(v1,v2))|
	}
\end{displaymath}

$\boxed{|s = P e|}$

\begin{displaymath}
	\frac{
		|aerr `notin` dom oenv|
	}{
		|load oenv eenv r (P e) F (extoenv oenv aerr (sem e eenv Bool)) (aerr,())|
	}
\end{displaymath}

$\boxed{|s = s1?|}$

\begin{displaymath}
	\frac{
		|r `notin` dom F| \quad |aerr `notin` dom oenv|
	}{
		|load oenv eenv r (s?) F (extoenv oenv aerr (returnM True)) (aerr,Nothing)|
	}
\end{displaymath}
\begin{displaymath}
	\frac{
		|r `inSet` dom F| \quad |aerr `notin` dom (prime oenv)| \quad |load oenv eenv r s F(prime oenv) v|
	}{
		|load oenv eenv r (s?) F (extoenv oenv aerr (app valid v)) (aerr,Just v)|
	}
\end{displaymath}

$\boxed{|s = flist s1 x e|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|aerr `notin` dom oenv| \quad
		|meval oenv (sem e eenv {tau}) (prime oenv) {t1,..,tk}| \\
		|meval (prime oenv) (forn 1 i k (doM { vi <- pload (exteenv eenv x ti) r s F; returnM (map ti vi) })) (prime2 oenv) vs|\\
		|eerr = forn 1 i k (doM { bi <- app valid (app vs ti); returnM (bigwedge bi) } )|
	\end{array}
	}{
		|load oenv eenv r (flist s x e) F (extoenv (prime2 oenv) aerr eerr) (aerr,vs)|
	}
\end{displaymath}

$\boxed{|store oenv eenv r s F v (prime oenv) (prime F) (prime phi)|}$ ``Under heap |oenv| and environment |eenv|, store the representation |v| for the specification |s| on filesystem |F| at path |r| and yield an updated filesystem |prime F| and a validation function |prime phi|.''

$\boxed{|s = M s1|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|app oenv a = e| \quad |meval oenv e (prime oenv) (aerr,v)| \\
		|store (prime oenv) eenv r s F v (prime2 oenv) (prime F) (prime phi)|
	\end{array}
	}{
		|store oenv eenv r (M s) F a (prime2 oenv) (prime F) (prime phi)|
	}
\end{displaymath}

$\boxed{|s = k|}$

\begin{displaymath}
	\frac{
		|meval oenv (storek k eenv F r (d,v)) (prime oenv) (prime F,phi) |
	}{
		|store oenv eenv r k F (aerr,(d,v)) (prime oenv) (prime F) phi|
	}
\end{displaymath}

\begin{displaymath}
	 |storek File eenv F r (i,u)| \left\{
	\begin{array}{ll}
		|returnM (extF F r (i,File u),lambda (prime F) ( app (prime F) (r) = (i,File u)))| & \quad \text{if}~ |i `neq` iinvalid| \\
		|returnM (extF F r bot,lambda (prime F) (app (prime F) (r) `neq` (_,File _)))| & \quad \text{if}~ |i = iinvalid `and` app F (r) = (_,File _)| \\
		|returnM (F,lambda (prime F) (app (prime F) (r) `neq` (_,File _)))| & \quad \text{if}~ |i = iinvalid `and` app F (r) `neq` (_,File _)|
	\end{array} \right.
\end{displaymath}

\begin{displaymath}
	 |storek Dir eenv F r (i,{u1,...,un})| \left\{
	\begin{array}{ll}
		|returnM (extF F r (i,Dir {u1,...,un}),lambda (prime F) ( app (prime F) (r) = (i,Dir {u1,...,un}) ))| & \quad \text{if}~ |i `neq` iinvalid| \\
		|returnM (extF F r bot,lambda (prime F) (app (prime F) (r) `neq` (_,Dir _)))| & \quad \text{if}~ |i = iinvalid `and` app F (r) = (_,Dir _)| \\
		|returnM (F,lambda (prime F) (app (prime F) (r) `neq` (_,Dir _)))| & \quad \text{if}~ |i = iinvalid `and` app F (r) `neq` (_,Dir _)|
	\end{array} \right.
\end{displaymath}

\begin{displaymath}
	 |storek Link eenv F r (i,prime r)| \left\{
	\begin{array}{ll}
		|returnM (extF F r (i,Link (prime r)),lambda (prime F) ( app (prime F) (r) = (i,Link (prime r))))| & \quad \text{if}~ |i `neq` iinvalid| \\
		|returnM (extF F r bot,lambda (prime F) (app (prime F) (r) `neq` (_,Link _)))| & \quad \text{if}~ |i = iinvalid `and` app F (r) = (_,Link _)| \\
		|returnM (F,lambda (prime F) (app (prime F) (r) `neq` (_,Link _)))| & \quad \text{if}~ |i = iinvalid `and` app F (r) `neq` (_,Link _)|
	\end{array} \right.
\end{displaymath}

$\boxed{|s = e :: s1|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|meval oenv (sem e eenv Path) (prime oenv) (prime r)|\\
		|store (prime oenv) eenv (prime r) s F v (prime2 oenv) (prime F) (prime phi)|
	\end{array}
	}{
		|store oenv eenv r (e :: s) F v (prime2 oenv) (prime F) (prime phi)|
	}
\end{displaymath}

$\boxed{|s = dpair x s1 s2|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|store oenv eenv r s1 F v1 oenv1 F1 phi1|\\
		|store oenv1 (exteenv eenv x v1) r s2 F v2 oenv2 F2 phi2|\\
		|phi = lambda (prime F) (app phi1 (prime F)) `and` (app phi2 (prime F))|
	\end{array}
	}{
		|store oenv eenv r (dpair x s1 s2) F (aerr,(v1,v2)) oenv2 (F1 `cat` F2) phi|
	}
\end{displaymath}

$\boxed{|s = P e|}$

\begin{displaymath}
	\frac{
		|phi = lambda (prime F) True|
	}{
		|store oenv eenv r (P e) F (aerr,()) oenv F phi|
	}
\end{displaymath}

$\boxed{|s = s1?|}$

\begin{displaymath}
	\frac{
		|phi = lambda (prime F) (r `notin` dom (prime F))|
	}{
		|store oenv eenv r (s?) F (aerr,Nothing) oenv (extF F r bot) phi|
	}
\end{displaymath}
\begin{displaymath}
	\frac{
	\begin{array}{c}
		|store oenv eenv r s F v (prime oenv) F1 phi1| \\
		|phi = lambda (prime F) (app phi1 (prime F) `and` r `inSet` dom (prime F))|
	\end{array}
	}{
		|store oenv eenv r (s?) F (aerr,Just v) oenv F1 phi|
	}
\end{displaymath}

$\boxed{|s = flist s1 x e|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|meval oenv (sem e eenv {tau}) (prime oenv) ts| \quad |vs = {t1 `mapsto` v1,...,tk `mapsto` vk}| \\
		|phi = lambda (prime F) (ts = {t1,...,tk} `and` bigwedge ( app phii (prime F) ))|\\
		|meval (prime oenv) (forn 1 i k (doM { (Fi,phii) <- (pstore (exteenv eenv x vi) r s F vi); returnM (F1 `cat` ... `cat` Fk,phi)} )) (prime2 oenv) (prime F) (prime phi)|
	\end{array}
	}{
		|store oenv eenv r (flist s x e) F (aerr,vs) oenv (prime F) (prime phi)|
	}
\end{displaymath}

%format (tyOf x t) = "{\vdash" x ":" t "}"

\begin{proposition}[Load Type Safety]
	If |load oenv eenv r s F (prime oenv) (prime v)| and |R s = tau| then |tyOf v tau|.
\end{proposition}

\begin{theorem}[LoadStore]
	If
	\begin{align*}
		|load oenv eenv r s F (prime oenv) v| \\
		|store (prime2 oenv) eenv r s F (prime v) (prime3 oenv) (prime F) (prime phi)|\\
		|v (simErr (prime oenv) (prime2 oenv)) (prime v)|
	\end{align*}
	then |F = prime F| and |app (prime phi) (prime F)|.
\end{theorem}

\begin{theorem}[StoreLoad]
	If
	\begin{align*}
		|store oenv eenv r s F v (prime oenv) (prime F) (prime phi)| \\
		|load (prime oenv) eenv r s F (prime2 oenv) (prime v)|
	\end{align*}
	then |app (prime phi) (prime F)| ~iff~ |v (simErr (prime oenv) (prime2 oenv)) (prime v)|
\end{theorem}

stronger than the original forest theorem: store validation only fails for impossible cases (when representation cannot be stored to the FS without loss)

weaker in that we don't track consistency of inner validation variables; equality of the values is modulo error information. in a real implementation we want to repair error information on storing, so that it is consistent with a subsequent load.

the error information is not stored back to the FS, so the validity predicate ignores it.

%\begin{lemma}[Load Non-Sharing]
%	All the memory addresses (of error and forest thunks) found by fully evaluating a the value in the result of load are distinct.
%	So that for a spec |dpair x ("a" :: M s) ("b" :: M s)| we never have |loadDelta (a,a) did|.
%\end{lemma}

\section{Forest Incremental Semantics}

Note that:
\begin{itemize}
	\item We have access to the old filelesystem, since filesystem deltas record the changes to be performed.
	\item We do not have access to the old environment, since variable deltas record the changes that already occurred.
\end{itemize}

%format dbotv = "{\delta_\bot}_v"
%format dbotvi = "{\delta_\bot}_{v_i}"

\begin{spec}
	df ::= addFile r u | addDir r | addLink r (prime r) | rem r | chgAttrs r i | df1 ; df2 | did
\end{spec}

\begin{spec}
	dv ::= dM da dv1 | dv1 `otimes` dv2 | map ti dbotvi | dv1? | did | ddelta
	dbotv ::= bot | dv
\end{spec}

\begin{spec}
	deltav ::= did | ddelta
\end{spec}

\begin{spec}
	(focus ((addFile (prime r) u)) F r) `def`			if (star F (prime r)) `inSet` (star F r) then addFile (prime r) u else did
	(focus ((addDir (prime r))) F r) `def`				if (star F (prime r)) `inSet` (star F r) then addDir (prime r) else did
	(focus ((addLink (prime r) (prime2 r))) F r) `def` 	if (star F (prime r)) `inSet` (star F r) then addLink (prime r) (prime2 r) else did
	(focus ((rem (prime r))) F r) `def` 				if (star F (prime r)) `inSet` (star F r) then rem (prime r) else did
	(focus ((chgAttrs (prime r) i)) F r) `def` 			if (star F (prime r)) `inSet` (star F r) then chgAttrs (prime r) i else did
	(focus (df1 ; df2) F r) `def` (focus df1 F r) ; focus df2 F1 r where F1 = ((focus df1 F r)) F
	(focus did F r) `def` did
\end{spec}


\begin{spec}
	 darrow v oenv dv (prime v) (prime oenv)
\end{spec}
the value delta maps |v| to |v'|

monadic expressions only read from the store and perform new allocations; they can't modify existing addresses.

For any expression application |e oenv = (prime oenv,v)|, we have |oenv = oenv `intersection` prime oenv|.

errors are computed in the background

\begin{displaymath}
	\frac{
		|(prime a) `notin` dom(oenv)|
	}{
		|mset oenv da deltae a e (extoenv oenv (prime a) e) (prime a) ddelta|
	}
	\quad
	\frac{
	}{
		|mset oenv did deltae a e (extoenv oenv a e) a ddelta|
	}
	\quad
	\frac{
	}{
		|mset oenv did did a e oenv a did|
	}
\end{displaymath}



$\boxed{|dload oenv eenv deenv r s F v df dv (prime oenv) (prime v) (prime deltav)|}$ ``Under heap |oenv|, environment |eenv| and delta environment |deenv|, incrementally load the specification |s| for the original filesystem |F| and original representation |v|, given filesystem changes |df| and representation changes |dv|, to yield an updated representation |prime v| with changes |prime deltav|.

\begin{displaymath}
	\frac{
		\Delta_\varepsilon ||_{fv(s)} = \emptyset
		\quad
		|focus df F r = did|
	}{
		|dload oenv eenv deenv r s F v df did oenv v did|
	}
\end{displaymath}

\begin{displaymath}
	\frac{
		|load oenv eenv r s (df F) (prime oenv) (prime v)|
	}{
		|dload oenv eenv deenv r s F v df dv (prime oenv) (prime v) ddelta|
	}
\end{displaymath}

$\boxed{|s = M s1|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|app oenv (a) = e| \quad |meval oenv e (prime oenv) (aerr,v)|\\
		|dload (prime oenv) eenv deenv r s F v df dv (prime2 oenv) (prime v) deltav| \quad |v = prime v|
	\end{array}
	}{
		|dload oenv eenv deenv r (M s) F a df (dM did (did `otimes` dv)) (prime2 oenv) a did|
	}
\end{displaymath}

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|app oenv (a) = e| \quad |meval oenv e (prime oenv) (aerr,v)|\\
		|dload (prime oenv) eenv deenv r s F v df dv oenv1 (prime v) deltav|\\

		|mset oenv1 daerr deltav aerr (valid (prime v)) oenv2 (prime aerr) deltaaerr|\\
		|mset oenv2 da deltaaerr a (returnM (prime aerr,prime v)) oenv3 (prime a) deltaa|
		
	\end{array}
	}{
		|dload oenv eenv deenv r (M s) F a df (dM da (daerr `otimes` dv)) oenv3 (prime a) deltaa|
	}
\end{displaymath}

$\boxed{|s = e :: s1|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		\Delta_\varepsilon ||_{fv(s)} = \emptyset \quad |meval oenv (sem (r / e) eenv Path) (prime oenv) (prime r)| \\ 
		|dload (prime oenv) eenv deenv (prime r) (e :: s) F v df dv (prime2 oenv) (prime v) deltav|
	\end{array}
	}{
		|dload oenv eenv deenv r (e :: s) F v df dv (prime2 oenv) (prime v) deltav|
	}
\end{displaymath}

$\boxed{|s = dpair x s1 s2|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|dload oenv eenv deenv r s1 F v1 df dv1 oenv1 (prime v1) deltav1|\\
		|dload oenv1 (exteenv eenv x (prime v1)) (exteenv deenv x deltav1) r s2 F v2 df dv2 oenv2 (prime v2) deltav2|\\
		|mset oenv2 daerr (deltav1 `and` deltav2) aerr (doM {b1 <- valid (prime v1); b2 <- valid (prime v2); returnM (b1 `and` b2) }) (prime oenv)(prime aerr) deltaaerr|
	\end{array}
	}{
		|dload oenv eenv deenv r (dpair x s1 s2) F (aerr,(v1,v2)) df (daerr `otimes` (dv1 `otimes` dv2)) (prime oenv) (prime aerr,(prime v1,prime v2)) deltaaerr|
	}
\end{displaymath}

$\boxed{|s = P e|}$

\begin{displaymath}
	\frac{
		\Delta_\varepsilon ||_{fv(e)} = \emptyset
	}{
		|dload oenv eenv deenv r (P e) F v df did oenv v did|
	}
\end{displaymath}

$\boxed{|s = s1?|}$

\begin{displaymath}
	\frac{
		|r `notin` dom (df F)| \quad
		|mset oenv daerr dv aerr (returnM True) (prime oenv) (prime aerr) deltaaerr|
	}{
		|dload oenv eenv deenv r (s?) F (aerr,Nothing) df (daerr `otimes` dv) (prime oenv) (aerr,Nothing) deltaaerr|
	}
\end{displaymath}

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|r `inSet` dom (df F)| \quad
		|dload oenv eenv deenv r s F v df dv (prime oenv) (prime v) deltav| \\
		|mset oenv daerr deltav aerr (app valid (prime v)) (prime oenv) (prime aerr) deltaaerr|
	\end{array}
	}{
		|dload oenv eenv deenv r (s?) F (aerr,Just v) df (daerr `otimes` dv?) (prime oenv) (aerr,Just (prime v)) deltaaerr|
	}
\end{displaymath}

$\boxed{|s = flist s x e|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|meval oenv (sem e eenv {tau}) oenv1 {t1,...,tk}|\\
		|meval oenv1 (forn 1 i k (doM { (vi,deltavi) <- pdloadx eenv deenv r s F vs df dvs ; returnM (map ti vi,bigwedge deltavi) })) oenv2 (prime vs,deltavs)|\\
		|mset oenv2 daerr deltavs aerr (forn 1 i k (doM { bi <- app valid (app (prime vs) ti); returnM (bigwedge bi) } )) (prime oenv)(prime aerr) deltaaerr|
	\end{array}
	}{
		|dload oenv eenv deenv r (flist s x e) F (aerr,vs) df (daerr `otimes` dvs) (prime oenv) (prime aerr,prime vs) deltaaerr|
	}
\end{displaymath}

\begin{displaymath}
	\frac{
		|t `inSet` dom (vs)| \quad
		|dload oenv (exteenv eenv x t) (exteenv deenv x did) r s F (app vs t) df (app dvs t) (prime oenv) (prime v) deltav|
	}{
		|dloadx oenv eenv deenv r s F (t,vs) df dvs (prime oenv) (prime v) deltav|
	}
\end{displaymath}

\begin{displaymath}
	\frac{
		|t `notin` dom (vs)| \quad
		|load oenv eenv r s (df F) (prime oenv) (prime v)|
	}{
		|dloadx oenv eenv deenv r s F (t,vs) df dvs (prime oenv) (prime v) ddelta|
	}
\end{displaymath}

$\boxed{|dstore oenv eenv deenv r s F v df dv (prime oenv) (prime F) (prime phi)|}$ ``Under heap |oenv|, environment |eenv| and delta environment |deenv|, store the representation |v| for the specification |s| on filesystem |F| at path |r|, given filesystem changes |df| and representation changes |dv|, and yield an updated filesystem |prime F| and a filesystem validation function |prime phi|.''

\begin{displaymath}
	\frac{
	\begin{array}{c}
		\Delta_\varepsilon ||_{fv(s)} = \emptyset
		\quad
		|focus df F r = did| \\
		|sense oenv eenv r s v rs| \quad
		|phi = lambda (prime F) (eqUnder F rs (prime F))|
	\end{array}
	}{
		|dstore oenv eenv deenv r s F v df did oenv F phi|
	}
\end{displaymath}

\begin{displaymath}
	\frac{
		|store oenv eenv r s (df F) v (prime oenv) (prime F) (prime phi)|
	}{
		|dstore oenv eenv deenv r s F v df dv (prime oenv) (prime F) (prime phi)|
	}
\end{displaymath}

$\boxed{|s = M s1|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|app oenv (a) = e| \quad |meval oenv e (prime oenv) (aerr,v)|\\
		|dstore (prime oenv) eenv deenv r s F v df dv (prime2 oenv) (prime F) (prime phi)|
	\end{array}
	}{
		|dstore oenv eenv deenv r (M s) F a df (dM da (daerr `otimes` dv)) (prime2 oenv) (prime F) (prime phi)|
	}
\end{displaymath}

$\boxed{|s = e :: s1|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		\Delta_\varepsilon ||_{fv(s)} = \emptyset \quad |meval oenv (sem (r / e) eenv Path) (prime oenv) (prime r)| \\ 
		|dstore (prime oenv) eenv deenv (prime r) (e :: s) F v df dv (prime2 oenv) (prime F) (prime phi)|
	\end{array}
	}{
		|dstore oenv eenv deenv r (e :: s) F v df dv (prime2 oenv) (prime F) (prime phi)|
	}
\end{displaymath}

$\boxed{|s = dpair x s1 s2|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|dstore oenv eenv deenv r s1 F v1 df dv1 oenv1 (prime F1) (prime phi1)|\\
		|dstore oenv1 (exteenv eenv x v1) (exteenv deenv x dv1) r s2 F v2 df dv2 oenv2 (prime F2) (prime phi2)|\\
		|phi = lambda (prime F) (app (prime phi1) (prime F1) `and` app (prime phi2) (prime F2))|
	\end{array}
	}{
		|dstore oenv eenv deenv r (dpair x s1 s2) F (aerr,(v1,v2)) df (daerr `otimes` (dv1 `otimes` dv2)) oenv2 (F1 `cat` F2) phi|
	}
\end{displaymath}

$\boxed{|s = P e|}$

\begin{displaymath}
	\frac{
		|phi = lambda (prime F) (returnM True)|
	}{
		|dstore oenv eenv deenv r (P e) F v df dv oenv F phi|
	}
\end{displaymath}

$\boxed{|s = s1?|}$

\begin{displaymath}
	\frac{
		|r `notin` dom (df F)| \quad
		|phi = lambda (prime F) (r `notin` dom (prime F))|
	}{
		|dstore oenv eenv deenv r (s?) F (aerr,Nothing) df (daerr `otimes` did) oenv F phi|
	}
\end{displaymath}

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|r `inSet` dom (df F)| \quad
		|dstore oenv eenv deenv r s F v df dv (prime oenv) F1 phi1| \\
		|phi = lambda (prime F) (app phi1 (prime F) `and` e `inSet` dom (prime F))|
	\end{array}
	}{
		|dstore oenv eenv deenv r (s?) F (aerr,Just v) df (daerr `otimes` dv?) (prime oenv) F1 phi|
	}
\end{displaymath}

$\boxed{|s = flist s x e|}$

\begin{displaymath}
	\frac{
	\begin{array}{c}
		|meval oenv (sem e eenv {tau}) (prime oenv) ts| \quad |vs = {t1 `mapsto` v1,...,tk `mapsto` vk}| \\
		|phi = lambda (prime F) (ts = {t1,...,tk} `and` bigwedge ( app phii (prime F) ))|\\
		|meval oenv1 (forin ti (dom vs) (doM { (Fi,phii) <- pdstore (exteenv eenv x ti) (exteenv deenv x did) r s F (app vs ti) df (app dvs ti) ; returnM (F1 `cat` ... `cat` Fk,phi) })) oenv2 (prime F,prime phi)|
	\end{array}
	}{
		|dstore oenv eenv deenv r (flist s x e) F (aerr,vs) df (daerr `otimes` dvs) oenv2 (prime F) (prime phi)|
	}
\end{displaymath}

$\boxed{|sense oenv eenv r s v rs|}$ ``Sensitivity of a forest specification in respect to a representation''

\begin{displaymath}
	\frac{
		|app oenv a = e|  \quad |meval oenv e (prime oenv) v| \quad
		|sense (prime oenv) eenv r s v rs|
	}{
		|sense oenv eenv r (M s) a rs|
	}
\end{displaymath}

\begin{displaymath}
	\frac{
		|sense oenv eenv r s v rs|
	}{
		|sense oenv eenv r (e :: s) v ({r} `union` rs)|
	}
\end{displaymath}

\begin{displaymath}
	\frac{
		|sense oenv eenv r s1 v1 rs1| \quad
		|sense oenv (exteenv eenv x v1) r s2 v2 rs2|
	}{
		|sense oenv eenv r (dpair x s1 s2) (aerr,(v1,v2)) (rs1 `union` rs2)|
	}
\end{displaymath}

\begin{displaymath}
	\frac{
	}{
		|sense oenv eenv r (P e) v {}|
	}
\end{displaymath}

\begin{displaymath}
	\frac{
	}{
		|sense oenv eenv r (s?) (aerr,Nothing) {r}|
	}
\end{displaymath}
\begin{displaymath}
	\frac{
		|sense oenv eenv r s v rs|
	}{
		|sense oenv eenv r (s?) (aerr,Just v) ({r} `union` rs)|
	}
\end{displaymath}

\begin{displaymath}
	\frac{
		|vs = {t1 `mapsto` v1,...,tk `mapsto` vk}| \quad
		|forn i 1 k (sense oenv (exteenv eenv x ti) r s vi ri)|
	}{
		|sense oenv eenv r (flist s x e) (aerr,vs) (bigunion ri)|
	}
\end{displaymath}

\begin{theorem}[Incremental Load Soundness]
	If
	\begin{align*}
		|load oenv eenv r s F1 oenv1 v1|\\
		|darrow v1 oenv1 dv1 (prime v1) oenv2|\\
		|dload oenv2 (prime eenv) deenv r s F1 (prime v1) df1 dv1 oenv3 v2 deltav1p|\\
		|load oenv1 (prime eenv) r s (df1 F1) oenv4 v3|
	\end{align*}
	then |v2 (simErr oenv3 oenv4) v3| and |(app valid v2) (simErr oenv3 oenv4) (app valid v3)|.
\end{theorem}

\begin{displaymath}
\xymatrix@@R=.7cm@@C=2cm{
	|F1| \ar@@{=>}[ddr]^{\mathtt{load}_\Delta}  \ar@@{~>}[d]_{|df1|} \ar[r]^{\mathtt{load}} & |v1| \ar@@{~>}[d]^{|dv1|} \\
	|F2| \ar[d]_{|id|} & |prime v1| \ar@@{~>}[d]^{|deltav1p|} \\
	|F2| \ar[r]^{\mathtt{load}} & |v2|
}
\end{displaymath}

\begin{lemma}[Incremental Load Stability]
	|dload oenv eenv deenv r (M s) F a df (dM did dv) (prime oenv) a deltaa|
\end{lemma}

\begin{theorem}[Incremental Store Soundness]
	If
	\begin{align*}
		|store oenv eenv r s F v1 oenv1 F1 phi1|\\
		|darrow v1 oenv1 dv1 v2 oenv2|\\
		|dstore oenv2 (prime eenv) deenv r s F1 v2 df1 dv1 oenv3 F2 phi2|\\
		|store oenv2 (prime eenv) r s (df1 F1) v2 oenv4 F3 phi3|
	\end{align*}
	then |F2 = F3| and |app phi2 F2 = app phi3 F3|.
\end{theorem}

\begin{displaymath}
\xymatrix@@R=.7cm@@C=2cm{
	|F| \ar@@{~>}[d]_{} & |v1| \ar@@{->}[d]^{|id|} \ar@@{->}[dl]^{\mathtt{store}} \\
	|F1| \ar@@{~>}[d]_{|df1|} \ar[r]_{\mathtt{load}} & |v1| \ar@@{~>}[d]^{|dv1|} \ar@@{=>}[ddl]_{\mathtt{store}_\Delta} \\
	|prime F1| \ar@@{~>}[d]_{} & |v2| \ar@@{->}[d]^{|id|} \ar@@{->}[dl]^{\mathtt{store}} \\
	|F2| \ar[r]_{\mathtt{load}} & |v2|
}
\end{displaymath}

\end{document}

