function solve_relaxation( node )
% function solves a relaxation of the optimization problem
% some of the variables may be fixed.
% the method for solving the relaxation is to solve a chain of LPs.
% generic form of such LP:
%-----------------------------------------------------------------
%
% min_x             x^T * node.Cost
%
% such that:        x(:) >= 0
%                   node.EQmatrix * x == node.EQvector
%                   node.INEQmatrix * x >= ones
%
%-----------------------------------------------------------------
% Where BnB_root.INEQmatrix are inequalities generated by previous
% (self and parents') partitions of the vertices of the 
% Adjacency matrix. Which obtained by solving min cut.
% When reaches max iterations - solves an sdp if necessary

% input: node - type BnBNode

%% intrinsic params
epsilon = 1e-6;
max_iter = 50;

%% parse extrinsic params
A = node.EQmatrix;
b = node.EQvector;
D = node.INEQmatrix;
d = node.INEQvector;

YalmipOps = node.Root.YalmipOps;  % set the solver and other yalmip options
sdp_flag = true;                  % can be set to false for time purposes


%% Set-up optimization's parameters
yalmip('clear');
num_of_vars = size(A,2);

x_var = sdpvar(num_of_vars, 1);                  % optimization variable (column vector)
Energy = node.Cost'*x_var;                       % objective
Constraints = [ x_var(:) >= 0, A*x_var == b ];   % linear constraints

if ~isempty(D)
    Constraints = [ Constraints , D*x_var>=d ];  % additional linear constraints
end

%% chain of LP relaxations

% initialization
iter_counter = 0;
continue_loop = true;

% loop of chain of LPs
while continue_loop
    
    % optimization step
    diagnostics = optimize(Constraints, Energy, YalmipOps);
    
    % diagnostics
    if diagnostics.problem == 1 % the problem is infeasible
        node.Prune_branch = true;
        return
    elseif ~any( ~([ 0 , 4 ] - diagnostics.problem))  % Problem with solver ( not numerical one )
        error(['Problem with solver: ',diagnostics.info])
    end
    
    % (reaches fractional feasible solution)
    
    % ----results analysis
    
    % energy of solution: lower bound for the optimization problem
    node.RLX_LB = double(Energy) + node.Energy_bias;
    
    % necessary condition
    if node.RLX_LB > (node.Root.BnB_UB + node.Root.UB_thresh)
        node.Prune_branch = true;
        return
    end
    
    % update solution
    node.X_LB = double(x_var);
    
    % if solution is connected - no need to add connectivity constraints
    if node.Adj_size == 1
        node.LP_iter_num = iter_counter + 1;
        node.projectSolution(A, b, D, d);
        return
    end
    
    % --- add edge connectivity ineq constraint ---
    
    in_eq = node.solve_mincut;
    
    % update constraints - adding cutting plane
    Constraints = [ Constraints , in_eq*x_var >= 1 ];
    D = [D ; in_eq]; d = [d ; 1];
    
    % stop if - solution is edge connected or reached max iteration
    continue_loop = (iter_counter < max_iter) && ~(in_eq*node.X_LB >= (1-epsilon));
    iter_counter = iter_counter + 1;
end

% update inequlities for node's children
node.LP_iter_num = iter_counter;
node.INEQmatrix = D;
node.INEQvector = d;

%% solve sdp if necessary
if sdp_flag && (iter_counter == max_iter)
    node.solve_sdp;   
end

%% project relaxed solution
node.projectSolution(A, b, D, d);